# Elm server pages (or something)


The idea is for page configs to include tasks for resolving flags, extract the
instructions for how to do those tasks, then do those tasks on the server and 
include the data as a variable in the served html file.

1. Page config includes a ResolverTask - the task to be resolved
2. Elm codegen creates an elm worker which outputs a stringified description of 
the task to be resolved for each page via a port
3. The build bash script wraps the worker in a js file, runs it and writes the 
output to a file.

The server serving the html files can then do the task(s) and provide the page 
with the data via flags. Alternatively it could be turned into a CGI type thing.



# Build


```bash
bash ./build.sh dev
```

```bash
bash ./build.sh prod
```


# Run


```bash
node server.mjs
```
    
