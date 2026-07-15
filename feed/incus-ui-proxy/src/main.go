// Command incus-ui-proxy presents the Incus web UI and REST API to a browser
// through a LuCI-authenticated HTTPS endpoint, using Incus's local unix socket as
// the backend. The unix socket is a full-trust admin channel with no client
// certificate, so a LuCI user who has already logged in reaches the UI without
// having to enrol a certificate in their browser.
//
// incusd serves both the static UI (at /ui/) and the API (at /1.0/, including the
// event stream and console/exec websockets) over the same socket, so a single
// reverse proxy covers the whole UI. httputil.ReverseProxy handles the websocket
// upgrades: it detects Connection: Upgrade, and after incusd answers 101 it pipes
// the two connections raw.
//
// Auth flow: LuCI scopes its own session cookie to /cgi-bin/luci, so it is not
// sent to this proxy's port and path. Instead the luci-app-incus menu hands the
// LuCI session id to /incus-auth?sid=..., which validates it against ubus and, on
// success, sets this proxy's own path=/ cookie and redirects to /ui/. Every later
// request is gated on that cookie (re-validated against ubus each time), so a
// logged-out or expired session immediately loses access.
package main

import (
	"bytes"
	"context"
	"crypto"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"flag"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"os"
	"os/exec"
	"strings"
)

func main() {
	var (
		listen   = flag.String("listen", ":9443", "address to listen on (keep off incus's own 8443)")
		socket   = flag.String("socket", "/var/lib/incus/unix.socket", "incus unix socket")
		cert     = flag.String("cert", "/etc/uhttpd.crt", "TLS certificate (empty for plain HTTP)")
		key      = flag.String("key", "/etc/uhttpd.key", "TLS private key")
		aclGroup = flag.String("acl-group", "luci-app-incus", "LuCI ACL group the session must be able to read")
		cookie   = flag.String("cookie", "incus_ui_proxy", "name of the proxy's own session cookie")
		noAuth   = flag.Bool("no-auth", false, "skip the LuCI session check (testing only)")
		loginURL = flag.String("login-url", "", "absolute URL to send unauthenticated users to; empty means https://<request-host>/cgi-bin/luci/ (LuCI on the standard port, not this proxy's port)")
	)
	flag.Parse()

	backend := &httputil.ReverseProxy{
		// The socket speaks plain HTTP; give it a fixed dummy authority and dial the
		// unix socket for every connection (including the websocket upgrade dial).
		Director: func(r *http.Request) {
			r.URL.Scheme = "http"
			r.URL.Host = "incus"
			r.Host = "incus"
		},
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
				return (&net.Dialer{}).DialContext(ctx, "unix", *socket)
			},
		},
	}

	secure := *cert != "" && *key != ""

	handler := func(w http.ResponseWriter, r *http.Request) {
		// The hand-off endpoint: LuCI redirects here with its session id. Validate it,
		// then set our own cookie so the browser presents it to /ui/ and /1.0/.
		if r.URL.Path == "/incus-auth" {
			sid := r.URL.Query().Get("sid")
			if !*noAuth && !sessionAllowed(sid, *aclGroup) {
				http.Redirect(w, r, loginTarget(r, *loginURL), http.StatusFound)
				return
			}
			http.SetCookie(w, &http.Cookie{
				Name:     *cookie,
				Value:    sid,
				Path:     "/",
				Secure:   secure,
				HttpOnly: true,
				SameSite: http.SameSiteStrictMode,
			})
			http.Redirect(w, r, "/ui/", http.StatusFound)
			return
		}

		if !*noAuth {
			c, err := r.Cookie(*cookie)
			if err != nil || !sessionAllowed(c.Value, *aclGroup) {
				http.Redirect(w, r, loginTarget(r, *loginURL), http.StatusFound)
				return
			}
		}

		if r.URL.Path == "/" {
			http.Redirect(w, r, "/ui/", http.StatusFound)
			return
		}
		backend.ServeHTTP(w, r)
	}

	srv := &http.Server{Addr: *listen, Handler: http.HandlerFunc(handler)}
	if secure {
		crt, err := loadCert(*cert, *key)
		if err != nil {
			log.Fatalf("incus-ui-proxy: load cert: %v", err)
		}
		srv.TLSConfig = &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{crt}}
		log.Printf("incus-ui-proxy: https %s -> %s", *listen, *socket)
		log.Fatal(srv.ListenAndServeTLS("", ""))
	}
	log.Printf("incus-ui-proxy: http %s -> %s", *listen, *socket)
	log.Fatal(srv.ListenAndServe())
}

// loadCert reads a certificate and key that may each be PEM or DER, independently.
// We reuse OpenWrt's /etc/uhttpd.crt and .key so the proxy presents the same cert
// as LuCI, but its px5g writes them for an embedded TLS library and the two files
// need not share an encoding (seen in the wild: a DER cert paired with a PEM key).
// Go's tls.X509KeyPair only accepts PEM, so detect and decode each side by itself.
func loadCert(certFile, keyFile string) (tls.Certificate, error) {
	cRaw, err := os.ReadFile(certFile)
	if err != nil {
		return tls.Certificate{}, err
	}
	kRaw, err := os.ReadFile(keyFile)
	if err != nil {
		return tls.Certificate{}, err
	}
	if isPEM(cRaw) && isPEM(kRaw) {
		return tls.X509KeyPair(cRaw, kRaw)
	}
	certDER, err := derBytes(cRaw)
	if err != nil {
		return tls.Certificate{}, errors.New("cert: " + err.Error())
	}
	keyDER, err := derBytes(kRaw)
	if err != nil {
		return tls.Certificate{}, errors.New("key: " + err.Error())
	}
	key, err := parseDERKey(keyDER)
	if err != nil {
		return tls.Certificate{}, err
	}
	return tls.Certificate{Certificate: [][]byte{certDER}, PrivateKey: key}, nil
}

func isPEM(b []byte) bool { return bytes.Contains(b, []byte("-----BEGIN")) }

// derBytes returns the raw DER, unwrapping a PEM block if the input is PEM.
func derBytes(raw []byte) ([]byte, error) {
	if !isPEM(raw) {
		return raw, nil
	}
	blk, _ := pem.Decode(raw)
	if blk == nil {
		return nil, errors.New("malformed PEM")
	}
	return blk.Bytes, nil
}

// parseDERKey accepts a DER private key in PKCS#8, SEC1 (EC), or PKCS#1 (RSA) form;
// OpenWrt's px5g defaults to an EC key, which lands as SEC1 or PKCS#8.
func parseDERKey(der []byte) (crypto.PrivateKey, error) {
	if k, err := x509.ParsePKCS8PrivateKey(der); err == nil {
		return k, nil
	}
	if k, err := x509.ParseECPrivateKey(der); err == nil {
		return k, nil
	}
	if k, err := x509.ParsePKCS1PrivateKey(der); err == nil {
		return k, nil
	}
	return nil, errors.New("unsupported DER private key (not PKCS#8, SEC1, or PKCS#1)")
}

// loginTarget builds where to bounce an unauthenticated caller. It uses the
// configured URL if set, otherwise LuCI's login on the request's host at the
// standard HTTPS port. It must not point at this proxy's own port, or a direct
// unauthenticated hit would just loop straight back here.
func loginTarget(r *http.Request, configured string) string {
	if configured != "" {
		return configured
	}
	host := r.Host
	if i := strings.IndexByte(host, ':'); i >= 0 {
		host = host[:i]
	}
	return "https://" + host + "/cgi-bin/luci/"
}

// sessionAllowed reports whether sid is a live LuCI session that may read the given
// ACL group. LuCI keeps login sessions as ubus session objects; rpcd returns
// access=false for unknown, expired or unprivileged sessions. The root login is
// granted every ACL group, so a logged-in administrator passes.
func sessionAllowed(sid, aclGroup string) bool {
	if !validSID(sid) || !validACLName(aclGroup) {
		return false
	}
	arg := `{"ubus_rpc_session":"` + sid + `","scope":"access-group","object":"` + aclGroup + `","function":"read"}`
	out, err := exec.Command("ubus", "-S", "call", "session", "access", arg).Output()
	if err != nil {
		return false
	}
	return strings.Contains(string(out), `"access":true`)
}

// validSID guards the shell/JSON boundary: a LuCI session id is 32 lowercase hex
// characters. Anything else is rejected before it can reach ubus.
func validSID(s string) bool {
	if len(s) != 32 {
		return false
	}
	for _, c := range s {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			return false
		}
	}
	return true
}

// validACLName keeps the (operator-set) ACL group name to a safe character set so it
// cannot break out of the JSON argument.
func validACLName(s string) bool {
	if s == "" || len(s) > 64 {
		return false
	}
	for _, c := range s {
		if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.') {
			return false
		}
	}
	return true
}
