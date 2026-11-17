# tap: stand-in "remote model" for the demo. Standard library only, no pip.
# Base pinned by digest (multi-arch index of python:3.14.10-slim-trixie).
FROM python:3.14.10-slim-trixie@sha256:9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f
WORKDIR /app
COPY tap.py /app/tap.py
USER 65534:65534
EXPOSE 8080
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
CMD ["python", "-I", "/app/tap.py"]
