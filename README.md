Elixirc
=======

Elixirc is a simply exploration in creating a concurrent chat server which is inspired by the IRC protocol. 

Commands
========
"register foo" -> registers a user with nickname foo
"change_nick bar" -> changes a users nick to bar, if they are already registered.
"list" -> lists the users currently present
"msg channel some message" -> sends "some message" to the channel "channel"
"join foobar" -> joins the channel "foobar"

Example usage=
=======
In a terminal, start the project via `iex -S mix`. 


In another terminal you can then log into the server using `nc localhost 4040`
