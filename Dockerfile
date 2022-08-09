FROM python:3.7.5-slim

ENV PYTHONUNBUFFERED=TRUE

RUN pip install --upgrade pip

RUN pip install grpcio  tensorflow flask keras-image-helper==0.0.1 gunicorn emacski/tensorflow-serving:latest-linux_arm64

WORKDIR /app

COPY "model_server.py" "model_server.py"

EXPOSE 9696

ENTRYPOINT ["gunicorn", "--bind", "0.0.0.0:9696", "model_server:app"]