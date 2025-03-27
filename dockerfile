FROM ruby:3.2

RUN gem install sinatra json rackup puma dotenv
WORKDIR /app
COPY . /app

EXPOSE 4567

CMD ["ruby", "app.rb", "-o", "0.0.0.0"]