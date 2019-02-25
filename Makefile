ifneq (,${NO_PROXY}${FTP_PROXY}${HTTP_PROXY}${HTTPS_PROXY})
PROXY_ARGS = env
endif
ifneq (,${NO_PROXY})
PROXY_ARGS += no_proxy=${NO_PROXY}
PROXY_ARGS += NO_PROXY=${NO_PROXY}
endif
ifneq (,${FTP_PROXY})
PROXY_ARGS += ftp_proxy=${FTP_PROXY}
PROXY_ARGS += FTP_PROXY=${FTP_PROXY}
endif
ifneq (,${HTTP_PROXY})
PROXY_ARGS += http_proxy=${HTTP_PROXY}
PROXY_ARGS += HTTP_PROXY=${HTTP_PROXY}
endif
ifneq (,${HTTPS_PROXY})
PROXY_ARGS += https_proxy=${HTTPS_PROXY}
PROXY_ARGS += HTTPS_PROXY=${HTTPS_PROXY}
endif

PROXY_ARGS += IMAGE_FORMAT=qcow2
PROXY_ARGS += IMAGE_SIZE=1G
PROXY_ARGS += ALPINE_MIRROR=http://dl-cdn.alpinelinux.org/alpine

.PHONY: run
run:
	@sudo $(PROXY_ARGS) $(CURDIR)/alpine-make-vm-image/alpine-make-vm-image $(CURDIR)/raw.img

.PHONY: clean
clean:
	@sudo rm -f $(CURDIR)/raw.img
