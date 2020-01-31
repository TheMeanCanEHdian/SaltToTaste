FROM python:3.8.1-slim

LABEL maintainer="TheMeanCanEHdian"

# environment variables
ENV SALTTOTASTE_DOCKER=True
ENV TZ=UTC

WORKDIR /app

COPY ./requirements.txt /app/requirements.txt

RUN \
  pip install --no-cache-dir --upgrade pip && \
  pip install --no-cache-dir -r requirements.txt

COPY . /app

CMD [ "python", "saltToTaste.py", "--datadir", "/config" ]

VOLUME /config
EXPOSE 8100
