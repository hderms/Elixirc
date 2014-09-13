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

    defstruct  operator: false, nick: "Guest", client: nil
    @type t :: %User{nick: String.t, client: pid}
    def create("") do
      #empty nicks not permitted
      raise ArgumentError, message: "Empty nicks not permitted"
    end

    @spec create(bitstring, pid) :: boolean  ;
    def create(nick, client) when is_bitstring(nick) and is_pid(client) do
      if valid_nick?(nick)  do
        #initialize an empty user and then sanitize the nick
        %User{client: client} |> sanitize_nick!(nick)
        true
      else
        false
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
    @spec format_nick(String.t) :: String.t
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
      true
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
    def remove_user_by_client(agent, client) do
      
      Agent.update(agent, fn list ->
                     bad_user = Enum.find(list, &(&1.client == client))
                     List.delete(list, bad_user)
                   end)
    end
    def fetch_user_by_client(agent, client) do
      
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
  defp read_line(client) do
    case :gen_tcp.recv(client, 0) do
      {:ok, data} ->  data
      {:error, closed} -> UserList.remove_user_by_client(:userlist, client)
    end
  end
  defp write_line(line, client) do
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
    Elixirc.ChatServer.
    write_line( "#{from.nick} :  #{sanitized_message}\n", to.client)
  end
  def send_all(_, from, message) do
    users = UserList.get(:userlist) 
          Enum.each(users, &(psend(nil,from,  &1, message)))

  end
end


defmodule Elixirc.CommandParser do
  alias Elixirc.UserList, as: UserList
  @moduledoc """
    The command parser is in charge of parsing incoming commands from clients and triggering the appropriate events to occur in response
  """
  def parse(line, client) do
    split_lines = Regex.split(~r/ /, line)  ;
    command = List.first(split_lines)
    #Perform the appropriate command based on the first
    #word of input
    result =  case command do
                "nick" -> register_nick(split_lines, client)
                "change_nick" -> change_nick(split_lines, client)
                "list" -> list(split_lines, client)
                "msg" -> msg(split_lines, client)
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

  defp msg(lines, client) do
    [head | rest] = lines
    user = UserList.
    fetch_user_by_client(:userlist, client)
    #Elixirc.MessageRelay.send(:message_relay,user, rest)
    Elixirc.MessageRelay.
    send_all(:message_relay,user, rest)
  end

  defp register_nick(lines, client) do
    UserList.add_user(:userlist, List.last(lines), client)
  end
end

