## The contents of this file are subject to the Mozilla Public License
## Version 1.1 (the "License"); you may not use this file except in
## compliance with the License. You may obtain a copy of the License
## at http://www.mozilla.org/MPL/
##
## Software distributed under the License is distributed on an "AS IS"
## basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
## the License for the specific language governing rights and
## limitations under the License.
##
## The Original Code is RabbitMQ.
##
## The Initial Developer of the Original Code is GoPivotal, Inc.
## Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.


defmodule ListParametersCommandTest do
  use ExUnit.Case, async: false
  import TestHelper

  @command RabbitMQ.CLI.Ctl.Commands.ListParametersCommand

  @vhost "test1"
  @user "guest"
  @root   "/"
  @component_name "federation-upstream"
  @key "reconnect-delay"
  @value "{\"uri\":\"amqp://\"}"

  setup_all do
    RabbitMQ.CLI.Distribution.start()
    node_name = get_rabbit_hostname
    :net_kernel.connect_node(node_name)

    {:ok, plugins_file} = :rabbit_misc.rpc_call(node_name,
                                                :application, :get_env,
                                                [:rabbit, :enabled_plugins_file])
    {:ok, plugins_dir} = :rabbit_misc.rpc_call(node_name,
                                               :application, :get_env,
                                               [:rabbit, :plugins_dir])
    {:ok, rabbitmq_home} = :rabbit_misc.rpc_call(node_name, :file, :get_cwd, [])

    {:ok, [enabled_plugins]} = :file.consult(plugins_file)

    opts = %{enabled_plugins_file: plugins_file,
             plugins_dir: plugins_dir,
             rabbitmq_home: rabbitmq_home}

    set_enabled_plugins(node_name, [:rabbitmq_metronome, :rabbitmq_federation], opts)

    add_vhost @vhost

    on_exit(fn ->
      set_enabled_plugins(get_rabbit_hostname,enabled_plugins,opts)
      delete_vhost @vhost
      :erlang.disconnect_node(get_rabbit_hostname)
      :net_kernel.stop()
    end)

    :ok
  end

  setup context do

    on_exit(fn ->
      clear_parameter context[:vhost], context[:component_name], context[:key]
    end)

    {
      :ok,
      opts: %{
        node: get_rabbit_hostname,
        timeout: (context[:timeout] || :infinity),
        vhost: context[:vhost]
      }
    }
  end

  test "validate: wrong number of arguments leads to an arg count error" do
    assert @command.validate(["this", "is", "too", "many"], %{}) == {:validation_failure, :too_many_args}
  end

  @tag component_name: @component_name, key: @key, value: @value, vhost: @vhost
  test "run: a well-formed, host-specific command returns list of parameters", context do
    vhost_opts = Map.merge(context[:opts], %{vhost: context[:vhost]})
    set_parameter(context[:vhost], context[:component_name], context[:key], @value)
    @command.run([], vhost_opts)
    |> assert_parameter_list(context)
  end

  test "run: An invalid rabbitmq node throws a badrpc" do
    target = :jake@thedog
    :net_kernel.connect_node(target)
    opts = %{node: target, vhost: @vhost, timeout: :infinity}

    assert @command.run([], opts) == {:badrpc, :nodedown}
  end

  @tag component_name: @component_name, key: @key, value: @value, vhost: @root
  test "run: a well-formed command with no vhost runs against the default", context do

    set_parameter("/", context[:component_name], context[:key], @value)
    on_exit(fn ->
      clear_parameter("/", context[:component_name], context[:key])
    end)

    @command.run([], context[:opts])
    |> assert_parameter_list(context)
  end

  @tag component_name: @component_name, key: @key, value: @value, vhost: @vhost
  test "run: zero timeout return badrpc", context do
    set_parameter(context[:vhost], context[:component_name], context[:key], @value)
    assert @command.run([], Map.put(context[:opts], :timeout, 0)) == {:badrpc, :timeout}
  end

  @tag component_name: @component_name, key: @key, value: @value, vhost: "bad-vhost"
  test "run: an invalid vhost returns a no-such-vhost error", context do
    vhost_opts = Map.merge(context[:opts], %{vhost: context[:vhost]})

    assert @command.run(
      [],
      vhost_opts
    ) == {:error, {:no_such_vhost, context[:vhost]}}
  end

  @tag vhost: @vhost
  test "run: multiple parameters returned in list", context do
    parameters = [
      %{vhost: @vhost, component: "federation-upstream", name: "my-upstream", value: "{\"uri\":\"amqp://\"}"},
      %{vhost: @vhost, component: "exchange-delete-in-progress", name: "my-key", value: "{\"foo\":\"bar\"}"}
    ]
    parameters
    |> Enum.map(
        fn(%{component: component, name: name, value: value}) ->
          set_parameter(context[:vhost], component, name, value)
          on_exit(fn ->
            clear_parameter(context[:vhost], component, name)
          end)
        end)

    params = for param <- @command.run([], context[:opts]), do: Map.new(param)

    assert MapSet.new(params) == MapSet.new(parameters)
  end

  @tag component_name: @component_name, key: @key, value: @value, vhost: @vhost
  test "banner", context do
    vhost_opts = Map.merge(context[:opts], %{vhost: context[:vhost]})

    assert @command.banner([], vhost_opts)
      =~ ~r/Listing runtime parameters for vhost \"#{context[:vhost]}\" \.\.\./
  end

  # Checks each element of the first parameter against the expected context values
  defp assert_parameter_list(params, context) do
    [param] = params
    assert MapSet.new(param) == MapSet.new([component: context[:component_name],
                                            name: context[:key],
                                            value: context[:value],
                                            vhost: context[:vhost]])
  end
end