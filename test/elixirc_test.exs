defmodule ElixircTest do
  use ExUnit.Case
  alias Elixirc.User, as: User
  alias Elixirc.UserList, as: UserList
  

  test "The Userlist agent spawns properly" do
    assert {:ok, _} = UserList.start_link()
  end
  test "The Userlist agent can push things" do
    {:ok, agent} = UserList.start_link()
    assert :ok = UserList.push(agent, "foo")
    assert ["foo"] = UserList.get(agent)
  end
  test "The Userlist allows user creation" do
    {:ok, agent} = UserList.start_link()
    UserList.add_user(agent,  "Bigboi")
    assert [%User{nick: "bigboi"}] = UserList.get(agent)
  end
  test "The Userlist agent wont allow creation of a user without a name" do
    {:ok, agent} = UserList.start_link()
    assert_raise ArgumentError,fn ->
      UserList.add_user(agent,  "")
    end
  end
  test "The Userlist agent wont allow creation of a user without a name" do
    {:ok, agent} = UserList.start_link()
    assert_raise ArgumentError,fn ->
      UserList.add_user(agent,  "")
    end
  end
test "The Userlist agent wont allow creation of a user with non-alpha characters" do
    {:ok, agent} = UserList.start_link()
    assert_raise ArgumentError,fn ->
      UserList.add_user(agent,  "#*$")
    end
  end



  test "The Userlist agent wont allow deletion of a user " do
    {:ok, agent} = UserList.start_link()
    assert_raise ArgumentError,fn ->
      UserList.remove_user(agent,  "")
    end
  end
  test "The Userlist allows user deletion" do
    {:ok, agent} = UserList.start_link()
    UserList.add_user(agent,  "Dre")
    UserList.add_user(agent,  "Bigboi")
    assert [%User{nick: "bigboi"}, %User{nick: "dre"}] = UserList.get(agent)
    assert :ok = UserList.remove_user(agent,  "Dre")
    assert [%User{nick: "bigboi"}]  = UserList.get(agent)
    assert :ok = UserList.remove_user(agent,  "Bigboi")
    assert []  = UserList.get(agent)
{:ok, agent2} = UserList.start_link()
    UserList.add_user(agent2,  "Bigboi")
    UserList.add_user(agent2,  "Dre")
    assert :ok = UserList.remove_user(agent2,  "Dre")
    assert [%User{nick: "bigboi"}]  = UserList.get(agent2)
    assert :ok = UserList.remove_user(agent2,  "Bigboi")
    assert []  = UserList.get(agent2)

  end



end
