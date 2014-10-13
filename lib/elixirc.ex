defmodule Elixirc do
  alias Elixirc.UserList, as: Userlist
  alias Elixirc.ChatServer, as: ChatServer
  alias Elixirc.CommandParser, as: CommandParser
  alias Elixirc.ConnectionHandler, as: ConnectionHandler
  alias Elixirc.ChannelList, as: ChannelList
  
  #TODO: Break out these nested modules into separate files but keep
  #the namespaces intact
  @port 4040
  @userlist_name Userlist
  def start(_key, _agent) do
    import Supervisor.Spec
    children = [
                 supervisor(Task.Supervisor, [[name: Elixirc.TaskSupervisor]]),
                 worker(Task, [ChatServer, :accept, [@port]]),
                 worker(Userlist, [[name: :userlist]]),
                 worker(ConnectionHandler, [[name: :connection_handler]]),
                 worker(ChannelList, [[name: :channel_list]]),


             ]

    opts = [strategy: :one_for_one, name: Elixirc.Supervisor]
    Supervisor.start_link(children, opts)
  end

  
  defmodule User do
    @moduledoc """
The User module is used to keep track of details regarding an individually registered user (registered presumably through 'nick' command)
"""
    defstruct  operator: false, nick: "Guest", client: nil, id: nil
    @type t :: %User{nick: String.t, client: pid}
    def create("") do
      #empty nicks not permitted
      raise ArgumentError, message: "Empty nicks not permitted"
    end

    @spec create(bitstring, port) :: boolean   ;
    def create(nick, client) when is_bitstring(nick) and is_port(client) do
      if valid_nick?(nick)  do
        #initialize an empty user and then sanitize the nick
        %User{client: client} |> sanitize_nick!(nick) |> add_id
      end
    end

    def valid_nick?(nick) when not is_bitstring(nick) do
      false
    end

    @spec valid_nick?(bitstring) :: boolean
    def valid_nick?(nick) do
      Regex.match?(~r/^\w+$/, nick)
    end

    defp sanitize_nick!(user, nick) do
      new_nick = nick |> format_nick
      %{user | nick: new_nick}
    end
    defp add_id(user) do
      %User{user | id: UUID.uuid1()}
    end

    @spec format_nick(String.t) :: String.t
    def format_nick(nick) do
      nick |> String.downcase |> String.rstrip
    end
  end
  defmodule ConnectionHandler do
    @name :connection_handler
    def start_link(opts) do
      Agent.start_link(fn -> HashSet.new end, opts)
    end
    def add(client) when is_port(client) do
      Agent.update(@name, fn set -> HashSet.put(set, client) end)
    end
    def is_member?(client) when is_port(client) do
      Agent.get(@name, fn set -> HashSet.member?(set, client) end)
    end
    def get() do
      Agent.get(@name, fn set -> set end)
    end
    def remove(client) when is_port(client) do
      Agent.update(@name, fn set -> HashSet.delete(set, client) end)
      IO.puts("Removed client. ")
    end
  end
  defmodule Channel do
    alias Elixirc.MessageRelay, as: MessageRelay
    defstruct topic: "", name: "", users: [], pid: nil
    def init(channel) do
      loop(channel)
    end
    def create("") do
      {:error, "Must give a name for a channel."}
    end
    def create(name)do
      sanitize_name = name |> sanitize_name
      channel = %Channel{name: sanitize_name}
      pid = spawn(Channel, :init, [channel])
      channel = %Channel{channel | pid: pid}
    end
    def sanitize_name(name) do
      name |> String.downcase
    end
    def loop(channel) do
      receive do
        {:msg, message, user} -> broadcast(message, channel, user)
        {:add_user, new_user} -> channel = add_user(new_user, channel)
        {:list_users} -> send_message(inspect(channel.users), channel)
      end
      loop(channel)
    end
    defp send_message(message, channel) do
      IO.puts("sending message: #{message}\n")
    end
    defp user_in_channel?(channel, user) do
      Enum.any?(channel.users, &(user.id == &1.id))
    end
    def broadcast(message, channel, user) do
      if user_in_channel?(channel,user) do
        MessageRelay.send_many(nil, user, channel.users, ["#{channel.name} >" | message]) 
      end
    end
    defp add_user(new_user, channel) do
      new_channel = %Channel{channel| users:  [new_user | channel.users]}
      IO.puts(inspect(new_channel))
      new_channel
    end
  end
  defmodule ChannelList do
    def start_link(opts) do
      Agent.start_link(fn -> [] end, opts)
    end
    def add_channel(channellist, name) do
      channel = Channel.create(name)
      Agent.update(channellist, fn list -> [channel | list] end) 
           channel
    end
    def get(channellist) do
      Agent.get(channellist, fn list -> list end) 
    end

    def join(channel, user) do
      send(channel.pid, {:add_user,  user})
    end
    def join_by_name(channellist, name, user) do
      channel = Agent.get(channellist, fn list -> Enum.find(list, &(&1.name == name
                                                      ))end )
      unless channel do
        channel = add_channel(channellist, name)
      end
      join(channel, user)
    end
    def broadcast_by_name(channellist, name, message, user) do
      channel = Agent.get(channellist, fn list -> Enum.find(list, &(&1.name == name))end )
      if channel do
        send(channel.pid, {:msg,  message,user})
      end
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

    @spec add_user(atom, String.t, any) :: any
    def add_user(agent,  nick, client) do
      new_user = User.create(nick, client)
      push(agent, new_user)
    end

    @spec change_nick(atom, String.t, pid) :: any
    def change_nick(agent,new_nick, client) do
      new_nick_formatted = User.format_nick(new_nick)
      Agent.update(agent, fn list ->
                     user = Enum.find(list, &(&1.client == client))
                     new_list = List.delete(list, user)
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

    def remove_user_by_client(agent, client) when is_port(client) do
      
      Agent.update(agent, fn list ->
                     bad_user = Enum.find(list, &(&1.client == client))
                     List.delete(list, bad_user)
                   end)
    end

    @spec fetch_user_by_client(atom, port) :: any
    def fetch_user_by_client(agent, client) when is_port(client) do
      
      Agent.get(agent, fn list ->
                  Enum.find(list, &(&1.client == client))
                end)
    end

  end
end
defmodule Elixirc.ChatServer do

  @moduledoc """
    The chat server is in charge of accepting incoming connections and delegating the handling of their input to the proper processes
    """
  alias Elixirc.UserList, as: UserList
  alias Elixirc.ConnectionHandler, as: ConnectionHandler

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
    line = read_line(client)
    case line do
      {:ok, data} -> Elixirc.CommandParser.parse(data, client)

      serve(client)
      {:error, _} ->  UserList.remove_user_by_client(:userlist, client)
      ConnectionHandler.remove(client);
      _ -> true
      serve(client)
    end
  end

  defp read_line(client) do
    :gen_tcp.recv(client, 0)
  end

  def write_line(line, client) do
    :gen_tcp.send(client, line)
  end

  def send_error(client, message) do
    write_line(message, client)
  end

end

defmodule Elixirc.MessageRelay do
  alias Elixirc.User, as: User
  alias Elixirc.UserList, as: UserList

  def psend(_, %User{} = from, %User{} = to, message) do
    IO.puts(inspect(message))
    sanitized_message =  message |> Enum.map(&(String.rstrip &1))
    |> (&(Enum.join(&1, " "))).()
    |> String.rstrip
IO.puts(inspect(from.nick))
    IO.puts(inspect(sanitized_message))

    Elixirc.ChatServer.
    write_line( "#{from.nick} :  #{sanitized_message}\n", to.client)
      end
  def send_many(_, from, to_users , message) do
    Enum.each(to_users, &(psend(nil,from,  &1, message)))
  end

  def send_all(_, from, message) do
    users = UserList.get(:userlist) 
          Enum.each(users, &(psend(nil,from,  &1, message)))
  end

end


defmodule Elixirc.CommandParser do
  alias Elixirc.UserList, as: UserList
  alias Elixirc.ConnectionHandler, as: ConnectionHandler
  alias Elixirc.ChannelList, as: ChannelList

  @moduledoc """
    The command parser is in charge of parsing incoming commands from clients and triggering the appropriate events to occur in response
  """

  def parse(line, client) do
    IO.puts(inspect(client))
    line = String.rstrip(line)
    split_lines = Regex.split(~r/ /, line)  ;
    command = List.first(split_lines)
    [head | rest ] = split_lines
    #Perform the appropriate command based on the first
    #word of input
    result =  case command do
                "register" -> register_nick(split_lines, client)
                "change_nick" -> change_nick(split_lines, client)
                "list" -> list(split_lines, client)
                "msg" -> chan_msg(rest, client)
                "join" -> join_channel(split_lines, client)
                _ -> IO.puts "no match for #{command} "
              end
    case result do
      #tell the client they have an error
      {:error, message} -> Elixirc.ChatServer.send_error(client, message)
      #otherwise just do nothing
      {:ok, _ } -> true
      _ -> true 
    end
  end

  defp list(list, client) do
    Elixirc.UserList.get(:userlist)
    |> Enum.map_join "\n", &(&1.nick) 
  end

  defp change_nick(lines, client) do
    UserList.change_nick(:userlist, List.last(lines), client)
  end
  defp join_channel(split_lines, client) do
    user = UserList.fetch_user_by_client(:userlist, client)
    IO.puts(inspect(split_lines))
    ChannelList.join_by_name(:channel_list, List.last(split_lines), user)
  end
  defp chan_msg(lines, client) do
    user = UserList.
    fetch_user_by_client(:userlist, client)
    #Elixirc./essageRelay.send(:message_relay,user, rest)
    [channel | rest ] = lines
    ChannelList.broadcast_by_name(:channel_list, channel, rest, user)
  end



  defp msg(lines, client) do
    [head | rest] = lines
    user = UserList.
    fetch_user_by_client(:userlist, client)
    #Elixirc./essageRelay.send(:message_relay,user, rest)
    Elixirc.MessageRelay.
    send_all(:message_relay,user, rest)
  end

  defp register_nick(lines, client) do
    unless ConnectionHandler.is_member?(client) do
      UserList.add_user(:userlist, List.last(lines), client)
      ConnectionHandler.add(client)
    else
      {:error, "User is already registered."}
    end
  end
end

