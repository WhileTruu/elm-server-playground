import express from 'express'
import path from 'path'
import { fileURLToPath } from 'url';
import fs from 'fs';
import { Elm } from './_site/worker.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const resolveTask = (task) => {
  switch (task) {
    case 'PosixTime':
      const timeNowMillis = Date.now();
      return timeNowMillis;
    case 'RandomInt32':
      const randomInt32 = Math.floor(Math.random() * 2**32);
      return randomInt32;
  }
}

const resolveAll = (tasks) => {
  const result = {};

  for (const task of tasks) {
    result[task] = resolveTask(task);
  }

  return result;
}

const main = Elm.Worker.init();

function getFlagsFor(resolve, key, data) {
  main.ports.put.subscribe(portCallback(main))
  main.ports.get.send([key, data])

  function portCallback(elmApp) {
    var f = function(effectResult) {
      elmApp.ports.put.unsubscribe(f)

      switch (effectResult.variant) {
        case 'EffectResultLabels':
          const obj = Object.assign(data, resolveAll(effectResult.payload))
          getFlagsFor(resolve, key,  obj)
          break;
        case 'EffectResultSuccess':
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
