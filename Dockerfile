# syntax=docker/dockerfile:1
#
# MailDigest container image. Two stages: the first builds the wheel from this
# checkout, the second installs only that wheel on a slim Python image and runs
# as an unprivileged user. Nothing in the image needs root, and the image holds
# no configuration and no secret -- both live on the /data volume or come in as
# MAILDIGEST_* environment variables (docs/OPERATIONS.md section 7).
#
# The base image is pinned by digest so the build is reproducible; Dependabot
# keeps the digest current (.github/dependabot.yml).

FROM python:3.13-slim@sha256:8d9d0b8bcf6506481eae4907c18f5e3e7902e629f5f6d684f9e7c32e85e3ddf0 AS builder
WORKDIR /src
COPY pyproject.toml README.md LICENSE ./
COPY src ./src
COPY man ./man
RUN pip install --no-cache-dir --upgrade build \
 && python -m build --wheel --outdir /wheels

FROM python:3.13-slim@sha256:8d9d0b8bcf6506481eae4907c18f5e3e7902e629f5f6d684f9e7c32e85e3ddf0

LABEL org.opencontainers.image.title="MailDigest" \
      org.opencontainers.image.description="The mail summariser you can hand a phishing mail to: reads a mirror mailbox, summarises with a language model, phishing-checks with a second one, delivers text-only digests to Telegram, Discord or Signal." \
      org.opencontainers.image.url="https://kpafi.github.io/maildigest/" \
      org.opencontainers.image.source="https://github.com/kpafi/maildigest" \
      org.opencontainers.image.documentation="https://github.com/kpafi/maildigest/blob/main/docs/OPERATIONS.md" \
      org.opencontainers.image.licenses="MIT"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    MAILDIGEST_CONFIG=/data/config.toml

# uid/gid 1000 matches the first user on most hosts, so a bind-mounted ./data
# is writable without any chown; docker-compose.yml lets you override it.
RUN groupadd --gid 1000 maildigest \
 && useradd --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin maildigest \
 && mkdir -p /data \
 && chown maildigest:maildigest /data

COPY --from=builder /wheels/*.whl /tmp/wheels/
RUN pip install --no-cache-dir /tmp/wheels/*.whl \
 && rm -rf /tmp/wheels \
 && maildigest --help > /dev/null

USER maildigest
WORKDIR /data
VOLUME ["/data"]

# SIGTERM finishes the running cycle and then stops (ADR-051); compose gives
# it 120 s for that.
STOPSIGNAL SIGTERM
ENTRYPOINT ["maildigest"]
CMD ["run"]
