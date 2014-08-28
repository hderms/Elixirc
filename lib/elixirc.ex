defmodule Elixirc do

  alias Elixirc.Userlist, as: Userlist
  alias Elixirc.CommandParser, as: CommandParser

  defmodule User do
    defstruct  operator: false, nick: "Guest"
    def create("") do
      #empty nicks not permitted
      raise ArgumentError, message: "Empty nicks not permitted"
    end
    def create(nick) when is_bitstring(nick) do
      if valid_nick?(nick)  do
        #initialize an empty user and then sanitize the nick
        %User{} |> sanitize_nick!(nick)
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
      nick |> String.downcase
    end
  end

  defmodule UserList do
    def start_link() do
      Agent.start_link fn -> [] end
    end

    defp push(agent, element) do
      Agent.update(agent, fn list -> [element | list] end)
    end

    def get(agent) do
      Agent.get(agent, fn list -> list end)
    end

    def add_user(_,  %User{nick: ""} = _) do
      raise ArgumentError, message: "User must have a nick"
    end

    def add_user(agent,  nick) do
      new_user = User.create(nick)
      push(agent, new_user)
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
  end

  defmodule ChannelList do
  end
  defmodule CommandParser do
    def parse(line) do
      split_lines = Regex.split(~r/ /, line) 
      IO.puts(split_lines)
                  command = List.first(split_lines)
      case command do
        "nick" -> IO.puts "Got a nick"
        _ -> IO.puts "no match for #{command} "
      end
    end
  end
  defmodule ExecutionRouter do
  end
  defmodule ConnectionHandler do
  end
  defmodule ChatServer do
    def accept(port) do 
        {:ok, socket} = :gen_tcp.listen(port, 
                                            [:binary, packet: :line,
                                             active: false])
        IO.puts "Accepting connections on port #{port}"
        loop_acceptor(socket)
    end
    defp loop_acceptor(socket) do
      {:ok, client} = :gen_tcp.accept(socket)
      serve(client)
      loop_acceptor(socket)
    end
    defp serve(client) do
      client 
          |> read_line()
          |> CommandParser.parse
      serve(client)
    end
    defp read_line(socket) do
      {:ok, data} = :gen_tcp.recv(socket, 0)
      data
    end
    defp write_line(line, socket) do
      :gen_tcp.send(socket, line)
    end
  end
end
