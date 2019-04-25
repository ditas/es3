# Erlang Simple Storage Service

**Stores large files in distributed manner**

## How to use
The simpliest way to use (**assuming you have erlang installed on your machine**) is `console.sh` file

```bash
chmod +x console.sh

./console.sh local
```

It starts the erlang console and application.
If you want to use this application in distributed way you will have to change 2 files
`config/vm.args` and `config/local/es3.config`

### Steps to use in distributed mode on local machine
1. Start first node as was said before
2. Change `config/vm.args` as shown below (you can use any name for the second node)
```text
-name b@127.0.0.1

-setcookie testCookieSet

+K true
+A 100
```
3. Change `config/local/es3.config` as shown below (use the name of first node which is `'a@127.0.0.1'` by default and change the `api_port` number to any different from the one used for the main node.
```erlang
[
    {es3, [
        {api_port, 5556},
        {nodes, [
            'a@127.0.0.1'
        ]},
        {chunk_size, 5000000}
    ]}
].
```
4. Start the second node via `./console.sh`. 

Definitely, you can use application in real world distributed way on different hosts. For this just use the real IP for each node in node names like `my_node1@10.123.123.1`.

## Sending files
To check the service just send some file via `curl`
```bash
curl -F test=123 -F 'file=@googlechrome.dmg' http://localhost:5555
```

## Receiving files
Use your favorite browser and go to the `http://localhost:5555/?action=read&name=googlechrome.dmg`

## Deleting files
Use your favorite browser and go to the `http://localhost:5555/?action=delete&name=googlechrome.dmg`

## How it works
Application starts with cowboy listener and application supervisor starts `chunk_controller` module.
When cowboy gets incoming request it starts API handler. API handler uses `chunk_controller` exported functions to initialize `chunk_handler` modules. Controller uses async cast to put each piece of file into handlers respectively it's number. Handlers write data to the file system.
So, main idea is to avoid RAM overflow in case of large file. Every handler process writes its piece of file asynchronously but as controller get the file by chunks that is unlikely to have this problem.
However, reading is made in synchronous way. Here is some space to improve the reading process by partial data preloading but it is a topic for another discussion.

***IN PROGRESS: add common tests***