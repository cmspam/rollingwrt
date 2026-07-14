'use strict';
'require view';
'require uci';

// This view hands the current LuCI session id to incus-ui-proxy and sends the
// browser there. LuCI scopes its own session cookie to /cgi-bin/luci, so it is
// not sent to the proxy's port; the proxy validates the session id, sets its own
// cookie, and redirects on to /ui/. The proxy port is read from UCI so it stays
// in step with the incus-ui-proxy service config.
return view.extend({
	load: function() {
		return uci.load('incus-ui-proxy');
	},

	render: function() {
		var listen = uci.get('incus-ui-proxy', 'main', 'listen') || ':8443';
		var port = String(listen).replace(/^.*:/, '') || '8443';
		var sid = (L.env && L.env.sessionid) ? L.env.sessionid : '';
		var url = 'https://' + window.location.hostname + ':' + port +
			'/incus-auth?sid=' + encodeURIComponent(sid);

		window.location.href = url;

		return E('div', { 'class': 'cbi-section' }, [
			E('h2', {}, _('Incus web UI')),
			E('p', {}, _('Opening the Incus web UI on port %s...').format(port)),
			E('p', {}, E('a', { 'href': url }, _('Click here if you are not redirected automatically.')))
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
