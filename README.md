# compile-nginx

Modified from i81b4u/tlsv1.3-nginx, compiled with the latest nginx and boringssl. And added systemctl configuration.

snippet of nginx config for boringssl:


	# SSL
	ssl_dyn_rec_enable on;
	ssl_ecdh_curve X25519MLKEM768:X25519:P-521:P-384:P-256;

	# QUIC
	http3 on;
	quic_retry on;

	# modern configuration
	ssl_prefer_server_ciphers on;
	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_ciphers [ECDHE-ECDSA-AES256-GCM-SHA384|ECDHE-RSA-AES256-GCM-SHA384]:[ECDHE-ECDSA-AES128-GCM-SHA256|ECDHE-RSA-AES128-GCM-SHA256];

