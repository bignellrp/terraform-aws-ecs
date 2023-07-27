FROM python:3.9

# Set working directory
WORKDIR /code

# Clone the conf files into the docker container
RUN git clone git clone https://github.com/bignellrp/footyapp.git /code/app

# Change to the pre branch
RUN git checkout pre

# Install the requirements
RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt

# Copy the app into the docker container
COPY ./app /code/app

RUN mkdir /tokens
COPY poststart.sh /tokens/tokens.json

ENV WEB_CONCURRENCY 1
ENV PYTHONUNBUFFERED 1

# Run the app
CMD ["gunicorn", "--conf", "app/gunicorn_conf.py", "--bind", "0.0.0.0:80", "app.main:app"]