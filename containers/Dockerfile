FROM --platform=linux/amd64 python:3.9

# Set working directory
WORKDIR /app

# Clone the conf files into the docker container
RUN git clone --branch preprod --single-branch https://github.com/bignellrp/footyapp.git /app

# Install the requirements
RUN pip install --no-cache-dir --upgrade -r /app/requirements.txt

# Copy the app config into the docker container
COPY ./config/gunicorn_conf.py /app/gunicorn_conf.py

# Move these to secrets
RUN mkdir /tokens
COPY tokens.json /tokens/tokens.json
COPY keys.json /tokens/keys.json

# Set environment variables
ENV WEB_CONCURRENCY 1
ENV PYTHONUNBUFFERED 1

# Run the app
CMD ["gunicorn", "--conf", "gunicorn_conf.py", "--bind", "0.0.0.0:80", "main:app"]