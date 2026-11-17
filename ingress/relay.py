"""ingress: a minimal TCP relay, 127.0.0.1:4000 on the host -> litellm:4000.

Why it exists: Docker cannot publish a port from a container that is only on an
`internal: true` network. This relay sits on both networks so that the gateway
itself (litellm) stays on the internal network with no route out.
It can only connect to LITELLM_HOST:LITELLM_PORT, inspects nothing and logs
nothing about the traffic it carries.
"""
import os
import socket
import threading

TARGET = (os.environ.get("LITELLM_HOST", "litellm"), int(os.environ.get("LITELLM_PORT", "4000")))


def pipe(src, dst):
    try:
        while data := src.recv(65536):
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def handle(client):
    try:
        upstream = socket.create_connection(TARGET, timeout=10)
        upstream.settimeout(None)
    except OSError:
        client.close()
        return
    threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
    pipe(upstream, client)
    client.close()
    upstream.close()


if __name__ == "__main__":
    server = socket.create_server(("0.0.0.0", 4000), reuse_port=False)
    print(f"ingress relay listening on :4000 -> {TARGET[0]}:{TARGET[1]}", flush=True)
    while True:
        conn, _ = server.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()
