FROM iojs:slim

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY package.json /usr/src/app/
RUN npm install

COPY src /usr/src/app/src
RUN npm run-script postinstall

CMD [ "npm", "start" ]
