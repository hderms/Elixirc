defmodule Elixirc do
  alias Elixirc.UserList, as: Userlist
  alias Elixirc.ChatServer, as: ChatServer
  alias Elixirc.CommandParser, as: CommandParser
  
  @userlist_name Userlist
  def start(port \\4040) do
    import Supervisor.Spec

    children = [
                 supervisor(Task.Supervisor, [[name: Elixirc.TaskSupervisor]]),
                 worker(Task, [ChatServer, :accept, [port]]),
                 worker(Userlist, [[name: :userlist]])

             ]

    opts = [strategy: :one_for_one, name: Elixirc.Supervisor]
    Supervisor.start_link(children, opts)
  end
  #TODO: Write these modules
  defmodule ChannelList do
  end
  defmodule ExecutionRouter do
  end
  defmodule ConnectionHandler do
  end
  defmodule User do
    @moduledoc """
The User module is used to keep track of details regarding an individually registered user (registered presumably through 'nick' command)
"""

    defstruct  operator: false, nick: "Guest", socket: nil
    def create("") do
      #empty nicks not permitted
      raise ArgumentError, message: "Empty nicks not permitted"
    end
    def create(nick, socket) when is_bitstring(nick) do
      if valid_nick?(nick)  do
        #initialize an empty user and then sanitize the nick
        %User{socket: socket} |> sanitize_nick!(nick)
      else 
      raise ArgumentError, message: "Nick invalid"
      end
    end
    def valid_nick?(nick) when not is_bitstring(nick) do
      false
    end
    def valid_nick?(nick) do
      Regex.match?(~r/^\w+$/, nick)
    end
    defp sanitize_nick!(user, nick) do
      new_nick = nick |> format_nick
      %{user | nick: new_nick}
    end
    def format_nick(nick) do
      nick |> String.downcase |> String.rstrip
    end
  end

  defmodule UserList do
    @name :userlist
    @moduledoc """
The User list is in charge of abstracting access to given users

"""
    alias Elixirc.User, as: User
    def init(opts) do
      {:ok, pid} = start_link(opts)
      {:ok, pid}
    end
    def start_link(opts) do
      Agent.start_link fn -> [] end,  opts
    end

    defp push(agent, element) do
      Agent.update(agent, fn list -> [element | list] end)
    end

    def get(agent) do
      Agent.get(agent, fn list -> list end)
    end

    def add_user(_,  %User{nick: ""} = _, _) do
      raise ArgumentError, message: "User must have a nick"
    end

    def add_user(agent,  nick, socket) do
      new_user = User.create(nick, socket)
      push(agent, new_user)
    end

    def change_nick(agent,new_nick, socket) do
      new_nick_formatted = User.format_nick(new_nick)
      Agent.update(agent, fn list ->
                     user = Enum.find(list, &(&1.socket == socket))
                     new_list = List.delete(list, user)
                     IO.puts "Found user #{user.nick}"
                     new_user = %{user| nick: new_nick_formatted}
                     [new_user | new_list]

                   end)


    end
    
    def remove_user(_, "") do
      raise ArgumentError, message: "User must have a nick"
    end

    def remove_user(agent, nick) when is_bitstring(nick) do
      new_nick = User.format_nick(nick)
      
      bad_user = Agent.get(agent, fn list ->
                             Enum.find(list, &(&1.nick == new_nick))
                           end)
      Agent.update(agent, fn list -> List.delete(list, bad_user) end)
    end
    def remove_user_by_socket(agent, socket) do
      
      Agent.update(agent, fn list ->
                     bad_user = Enum.find(list, &(&1.socket == socket))
                     List.delete(list, bad_user)
                   end)
    end
    def fetch_user_by_socket(agent, socket) do
      
      Agent.get(agent, fn list ->
                  Enum.find(list, &(&1.socket == socket))
                end)
    end


  end
end
defmodule Elixirc.ChatServer do
  @moduledoc """
The chat server is in charge of accepting incoming connections and delegating the handling of their input to the proper processes
"""
  alias Elixirc.UserList, as: UserList
  def start(port) do
    accept( port)
  end
  def accept( port) do 
      {:ok, socket} = :gen_tcp.listen(port, 
                                          [:binary, packet: :line,
                                           active: false])
      IO.puts "Accepting connections on port #{port}"
      loop_acceptor( socket)
  end
  defp loop_acceptor( socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    Task.Supervisor.start_child(Elixirc.TaskSupervisor, fn -> serve(client) end)
    loop_acceptor( socket)
  end
  defp serve(client) do
    client 
        |> read_line()
        |> (&(Elixirc.CommandParser.parse &1, client)).()
        serve(client)
  end
  defp read_line(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->  data
      {:error, closed} -> UserList.remove_user_by_socket(:userlist, socket)
    end
  end
  defp write_line(line, socket) do
    :gen_tcp.send(socket, line)
  end
  def send_error(socket, message) do
    write_line(message, socket)
  end
end

defmodule Elixirc.MessageRelay do
  alias Elixirc.User, as: User
  alias Elixirc.UserList, as: UserList
  def send(_,  nil, message) do
    {:error, "Error sending message"}
  end

  def psend(_, %User{} = from, %User{} = to, message) do
    IO.puts(inspect(message))
    sanitized_message =  message |> Enum.map(&(String.rstrip &1))
    |> (&(Enum.join(&1, " "))).()
    |> String.rstrip
    Elixirc.ChatServer.
    write_line( "#{from.nick} :  #{sanitized_message}", to.socket)
  end
  def send_all(_, from, message) do
    users = UserList.get(:userlist) 
          IO.puts(inspect(users))
          Enum.each(users, &(psend(nil,from,  &1, message)))

  end
end


defmodule Elixirc.CommandParser do
  @moduledoc """
The command parser is in charge of parsing incoming commands from clients and triggering the appropriate events to occur in response
"""
  def parse(line, socket) do
    IO.puts(inspect(line))
    split_lines = Regex.split(~r/ /, line) 
                IO.puts(split_lines)
                command = List.first(split_lines)
                result =  case command do
                            "nick" -> Elixirc.UserList.
                            add_user(:userlist, List.last(split_lines), socket)
                            "change_nick"
                            -> Elixirc.UserList.
                            change_nick(:userlist, List.last(split_lines), socket)
                            "list" -> Elixirc.UserList.get(:userlist)
                            |> Enum.map_join "\n", &(&1.nick) 
                                   |> IO.puts
                                   "msg" -> [head | rest] = split_lines
                                   user = Elixirc.UserList.
                                   fetch_user_by_socket(:userlist, socket)
                                   #Elixirc.MessageRelay.send(:message_relay,user, rest)
                                   Elixirc.MessageRelay.
                                   send_all(:message_relay,user, rest)
                                   
                                   _ -> IO.puts "no match for #{command} "
                          end
                case result do
                  {:error, message} -> Elixirc.ChatServer.send_error(socket, message)
                  _ -> true
                end

  end
end
