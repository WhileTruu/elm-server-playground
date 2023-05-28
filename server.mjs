import express from 'express'
import path from 'path'
import { fileURLToPath } from 'url';
import fs from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const resolveKeyTaskMap = JSON.parse(fs.readFileSync(path.join(__dirname, "/_site/worker.json")));

const resolve = (task) => {
  switch (task) {
    case 'ResolverTaskTimeNowMillis':
      const timeNowMillis = Date.now();
      return timeNowMillis;
    case 'ResolverTaskRandomSeed':
      const randomInt32 = Math.floor(Math.random() * 2**32);
      return randomInt32;
  }
}

const resolveAll = (key) => {
  console.log(key)
  const result = {};

  for (const task of resolveKeyTaskMap[key]) {
    result[task] = resolve(task);
  }
  console.log(result)

  return result;
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

    const fileContents = buff
        .toString()
        .replace(
            "// REPLACE_ME_WITH_FLAGS",
            `var flags = ${JSON.stringify(resolveAll("Pages.Home"))};`
        )

    res.send(fileContents);
  })
})

server.listen(port, () => {
  console.log(`Server started at http://localhost:${port}`)
})