FROM python:3.12
RUN apt-get update && \
    apt-get -y install tini && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
WORKDIR /app
COPY requirements.txt /app
RUN pip install --no-cache-dir -r requirements.txt
COPY uploader /app

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python", "uploader.py"]
