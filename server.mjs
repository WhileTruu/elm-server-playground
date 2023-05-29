import express from 'express'
import path from 'path'
import { fileURLToPath } from 'url';
import fs from 'fs';
import { Elm } from './_site/worker.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const fetchResToMetadata = (res) => ({
  url: res.url,
  statusCode: res.status,
  statusText: res.statusText,
  headers: Object.fromEntries(res.headers.entries()),
})

const fetchResToResponse = (res, text) => ( {
  variant: 200 <= res.status && res.status < 300 ? 'GoodStatus' : 'BadStatus',
  metadata: fetchResToMetadata(res),
  value: text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;"),
})


const resolveEffect = (effect) => {
  return new Promise((resolve, reject) => {
    switch (effect.effectKind) {
      case 'PosixTime':
        const timeNowMillis = Date.now();
        resolve(timeNowMillis)
        break
      case 'RandomInt32':
        const randomInt32 = Math.floor(Math.random() * 2**32)
        resolve(randomInt32)
        break
      case 'Http':
        fetch(effect.payload.url)
          .then(res =>
            res.text()
              .then(text => resolve(fetchResToResponse(res, text)))
          )
          .catch((err) => {
            console.log(err)
            resolve({variant: 'NetworkError'})
          })
        break
    }
  })
}

const main = Elm.Worker.init();

function getFlagsFor(resolve, key, data) {
  main.ports.put.subscribe(portCallback(main))
  main.ports.get.send([key, data])

  function portCallback(elmApp) {
    var f = function(effectResult) {
      elmApp.ports.put.unsubscribe(f)

      switch (effectResult.variant) {
        case 'Loop':
          Promise.all(effectResult.batch.map(resolveEffect)).then((resolved) => {
            const obj = Object.fromEntries(effectResult.batch.map((val, i) => [val.hash, resolved[i]]))
            getFlagsFor(resolve, key, Object.assign(data, obj))
          })
          break;

        case 'Done':
          resolve(data)
          break;

      }
    };
    return f;
  }
}

const server = express()
const port = process.env.PORT || 8080

server.get('/', (req, res, next) => {
  const filePath = path.join(__dirname, "/_site/home.html")

  fs.readFile(filePath, (err, buff) => {
    if (err) {
      console.error(err);
      next(err)
      return;
    }

    const flags = new Promise(resolve => getFlagsFor(resolve, "Pages.Home", {}))
    flags.then((resolvedFlags) => {
        const fileContents = buff
            .toString()
            .replace(
                "// REPLACE_ME_WITH_FLAGS",
                `var flags = ${JSON.stringify(resolvedFlags)};`
            )

      res.send(fileContents);
    })

  })
})

server.listen(port, () => {
  console.log(`Server started at http://localhost:${port}`)
})
