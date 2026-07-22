/* rollingwrt-pcr11-predict: predict the PCR 11 an sd-stub UKI will produce.
 *
 * sd-stub measures each present UKI PE section into PCR 11 (TPM2_PCR_KERNEL_BOOT)
 * in the order of systemd's unified_sections enum. Per section it extends twice:
 *   1. the section NAME as an ASCII string INCLUDING its NUL terminator (strsize8)
 *   2. the section CONTENT, memory_size (PE VirtualSize) bytes
 * .pcrsig is never measured (it is the signature over the expected PCR values).
 * The TPM extend is:  PCR = SHA256(PCR || SHA256(measured_bytes)), PCR starts
 * at 32 zero bytes (PCR 11 is not a firmware PCR).
 *
 * We assemble the UKI ourselves, so we know the exact section bytes; this
 * reproduces the measurement deterministically. Output: PCR 11 as lowercase hex.
 *
 * Verified byte-for-byte against a real vTPM boot's PCR 11 in the rollingWRT
 * boot test (that comparison is the acceptance gate for this tool).
 *
 * Build: cc -O2 -o rollingwrt-pcr11-predict rollingwrt-pcr11-predict.c -lcrypto
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <openssl/sha.h>

/* systemd unified_sections order (src/boot/unified-section.h). We measure the
 * ones that are present in this order; names we ship are all <= 8 chars so they
 * fit the PE section name field. .pcrsig is intentionally absent from this list. */
static const char *const SECTIONS[] = {
	".linux", ".osrel", ".cmdline", ".initrd", ".ucode", ".splash",
	".dtb", ".dtbauto", ".hwids", ".uname", ".profile", ".sbat", ".pcrpkey",
	NULL,
};

static uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static uint32_t rd32(const uint8_t *p) {
	return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint8_t pcr[32]; /* PCR 11 accumulator, starts at all-zero */

static void extend(const uint8_t *data, size_t len) {
	uint8_t dig[32], cat[64];
	SHA256(data, len, dig);        /* hash the measured bytes */
	memcpy(cat, pcr, 32);
	memcpy(cat + 32, dig, 32);
	SHA256(cat, 64, pcr);          /* PCR = SHA256(PCR || digest) */
}

/* find a section by name in the PE section table; return 1 and fill out params */
static int find_section(const uint8_t *buf, size_t buflen, const char *name,
                        uint32_t *vsize, uint32_t *rawsize, uint32_t *rawptr) {
	if (buflen < 0x40 || buf[0] != 'M' || buf[1] != 'Z') return 0;
	uint32_t pe = rd32(buf + 0x3c);
	if ((size_t)pe + 24 > buflen || memcmp(buf + pe, "PE\0\0", 4) != 0) return 0;
	uint16_t nsec = rd16(buf + pe + 6);
	uint16_t optsz = rd16(buf + pe + 20);
	size_t sect = pe + 24 + optsz;
	size_t nlen = strlen(name);
	for (uint16_t i = 0; i < nsec; i++) {
		const uint8_t *s = buf + sect + (size_t)i * 40;
		if ((size_t)(s - buf) + 40 > buflen) return 0;
		/* name field is 8 bytes, NUL-padded (no NUL if exactly 8 chars) */
		if (memcmp(s, name, nlen) != 0) continue;
		if (nlen < 8 && s[nlen] != 0) continue;
		*vsize = rd32(s + 8);
		*rawsize = rd32(s + 16);
		*rawptr = rd32(s + 20);
		return 1;
	}
	return 0;
}

int main(int argc, char **argv) {
	if (argc != 2) { fprintf(stderr, "usage: %s <uki.efi>\n", argv[0]); return 2; }

	FILE *f = fopen(argv[1], "rb");
	if (!f) { perror("open"); return 1; }
	fseek(f, 0, SEEK_END);
	long fsz = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (fsz <= 0) { fprintf(stderr, "empty file\n"); fclose(f); return 1; }
	uint8_t *buf = malloc((size_t)fsz);
	if (!buf || fread(buf, 1, (size_t)fsz, f) != (size_t)fsz) {
		fprintf(stderr, "read failed\n"); free(buf); fclose(f); return 1;
	}
	fclose(f);

	/* refuse anything that is not a valid PE UKI: returning a bogus (e.g. all
	 * zero) PCR would seal the LUKS key to an unusable policy. Erroring here
	 * makes the caller fall back to the passphrase instead. */
	uint32_t vs, rs, rp;
	if (!find_section(buf, (size_t)fsz, ".linux", &vs, &rs, &rp)) {
		fprintf(stderr, "%s: not an sd-stub UKI (no .linux section)\n", argv[0]);
		free(buf);
		return 1;
	}

	int measured = 0;
	for (int i = 0; SECTIONS[i]; i++) {
		uint32_t vsize, rawsize, rawptr;
		if (!find_section(buf, (size_t)fsz, SECTIONS[i], &vsize, &rawsize, &rawptr))
			continue; /* section not present in this UKI */
		if (vsize == 0) continue;
		measured++;

		/* 1. measure the section name, ASCII, including the NUL terminator */
		extend((const uint8_t *)SECTIONS[i], strlen(SECTIONS[i]) + 1);

		/* 2. measure the section content: VirtualSize bytes as loaded in memory,
		 *    i.e. min(VirtualSize, SizeOfRawData) file bytes then zero padding. */
		uint8_t *content = calloc(1, vsize);
		if (!content) { fprintf(stderr, "oom\n"); free(buf); return 1; }
		uint32_t ncopy = rawsize < vsize ? rawsize : vsize;
		if ((size_t)rawptr + ncopy <= (size_t)fsz)
			memcpy(content, buf + rawptr, ncopy);
		extend(content, vsize);
		free(content);
	}
	free(buf);

	if (measured == 0) {
		fprintf(stderr, "%s: no measurable sections found\n", argv[0]);
		return 1;
	}

	for (int i = 0; i < 32; i++) printf("%02x", pcr[i]);
	printf("\n");
	return 0;
}
