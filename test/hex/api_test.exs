defmodule Hex.APITest do
  use HexTest.Case
  @moduletag :integration

  test "user" do
    assert {401, _} = Hex.API.User.get("test_user", [key: "something wrong"])
    assert {201, _} = Hex.API.User.new("test_user", "test_user@mail.com", "hunter42")

    HexWeb.User.get(username: "test_user")
    |> HexWeb.User.confirm

    auth = [user: "test_user", pass: "hunter42"]
    assert {200, body} = Hex.API.User.get("test_user", auth)
    assert body["username"] == "test_user"
  end

  test "package" do
    auth = [user: "user", pass: "hunter42"]

    assert {404, _} = Hex.API.Package.get("apple")
    assert {201, _} = Hex.API.Package.new("apple", %{description: "foobar"}, auth)
    assert {200, body} = Hex.API.Package.get("apple")
    assert body["meta"]["description"] == "foobar"
  end

  test "release" do
    auth = [user: "user", pass: "hunter42"]
    Hex.API.Package.new("pear", %{}, auth)
    Hex.API.Package.new("grape", %{}, auth)

    tar = Hex.Tar.create(%{name: :pear, app: :pear, version: "0.0.1", requirements: %{}}, [])
    assert {404, _} = Hex.API.Release.get("pear", "0.0.1")
    assert {201, _} = Hex.API.Release.new("pear", tar, auth)
    assert {200, body} = Hex.API.Release.get("pear", "0.0.1")
    assert body["requirements"] == %{}

    tar = Hex.Tar.create(%{name: :grape, app: :grape, version: "0.0.2", requirements: %{pear: "~> 0.0.1"}}, [])
    reqs = %{"pear" => %{"app" => "pear", "requirement" => "~> 0.0.1", "optional" => false}}
    assert {201, _} = Hex.API.Release.new("grape", tar, auth)
    assert {200, body} = Hex.API.Release.get("grape", "0.0.2")
    assert body["requirements"] == reqs

    assert {204, _} = Hex.API.Release.delete("grape", "0.0.2", auth)
    assert {404, _} = Hex.API.Release.get("grape", "0.0.2")
  end

  test "docs" do
    auth = [user: "user", pass: "hunter42"]
    Hex.API.Package.new("tangerine", %{}, auth)

    tar = Hex.Tar.create(%{name: :tangerine, app: :tangerine, version: "0.0.1", requirements: %{}}, [])
    assert {201, _} = Hex.API.Release.new("tangerine", tar, auth)

    tarball = Path.join(tmp_path, "docs.tar.gz")
    :ok = :erl_tar.create(tarball, [{'index.html', "heya"}], [:compressed])
    tar = File.read!(tarball)

    assert {201, _} = Hex.API.ReleaseDocs.new("tangerine", "0.0.1", tar, auth)
    assert {200, ^tar} = Hex.API.ReleaseDocs.get("tangerine", "0.0.1")

    assert {204, _} = Hex.API.ReleaseDocs.delete("tangerine", "0.0.1", auth)
    assert {404, _} = Hex.API.ReleaseDocs.get("tangerine", "0.0.1")
  end

  test "registry" do
    HexWeb.RegistryBuilder.rebuild
    assert {200, _} = Hex.API.Registry.get
  end

  test "keys" do
    auth = [user: "user", pass: "hunter42"]
    assert {201, body} = Hex.API.Key.new("macbook", auth)
    assert byte_size(body["secret"]) == 32

    assert {201, _} = Hex.API.Package.new("melon", %{}, [key: body["secret"]])

    assert {200, body} = Hex.API.Key.get(auth)
    assert Enum.find(body, &(&1["name"] == "macbook"))

    assert {204, _} = Hex.API.Key.delete("macbook", auth)

    assert {200, body} = Hex.API.Key.get(auth)
    refute Enum.find(body, &(&1["name"] == "macbook"))
  end

  test "owners" do
    auth = [user: "user", pass: "hunter42"]
    Hex.API.Package.new("orange", %{}, auth)
    Hex.API.User.new("orange_user", "orange_user@mail.com", "hunter42")

    assert {200, [%{"username" => "user"}]} = Hex.API.Package.Owner.get("orange", auth)

    assert {204, _} = Hex.API.Package.Owner.add("orange", "orange_user@mail.com", auth)

    assert {200, [%{"username" => "user"}, %{"username" => "orange_user"}]} =
           Hex.API.Package.Owner.get("orange", auth)

    assert {204, _} = Hex.API.Package.Owner.delete("orange", "orange_user@mail.com", auth)

    assert {200, [%{"username" => "user"}]} = Hex.API.Package.Owner.get("orange", auth)
  end

  test "x-hex-message" do
    Hex.API.Utils.handle_hex_message('"oops, you done goofed"')
    refute_received {:mix_shell, _, _}

    Hex.API.Utils.handle_hex_message('  "oops, you done goofed" ; level = warn')
    assert_received {:mix_shell, :info, ["API warning: oops, you done goofed"]}

    Hex.API.Utils.handle_hex_message('"oops, you done goofed";level=fatal  ')
    assert_received {:mix_shell, :error, ["API error: oops, you done goofed"]}
  end
end
