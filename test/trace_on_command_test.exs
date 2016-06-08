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


defmodule TraceOnCommandTest do
  use ExUnit.Case, async: false
  import TestHelper

  @test_vhost "test"
  @default_vhost "/"

  setup_all do
    RabbitMQCtl.start_distribution(%{})
    :net_kernel.connect_node(get_rabbit_hostname)
    add_vhost(@test_vhost)

    on_exit([], fn ->
      delete_vhost(@test_vhost)
      :erlang.disconnect_node(get_rabbit_hostname)
      :net_kernel.stop()
    end)

    :ok
  end

  setup context do
    on_exit(context, fn -> trace_off(context[:vhost]) end)
    {:ok, opts: %{node: get_rabbit_hostname, vhost: context[:vhost]}}
  end

  test "merge_defaults: on an active node, trace_on command works on default" do
    opts = %{node: get_rabbit_hostname}
    opts_with_vhost = %{node: get_rabbit_hostname, vhost: "/"}

    assert TraceOnCommand.merge_defaults([], opts) == {[], opts_with_vhost} 

    trace_off(@default_vhost)
  end

  test "validate: wrong number of arguments triggers arg count error" do
    assert TraceOnCommand.validate(["extra"], %{}) == {:validation_failure, :too_many_args}
  end

  test "run: on an invalid RabbitMQ node, return a nodedown" do
    target = :jake@thedog
    :net_kernel.connect_node(target)
    opts = %{node: target, vhost: "/"}

    assert TraceOnCommand.run([], opts) == {:badrpc, :nodedown}
  end

  @tag vhost: @default_vhost
  test "run: calls to trace_on are idempotent", context do
    TraceOnCommand.run([], context[:opts])
    assert TraceOnCommand.run([], context[:opts]) == :ok
  end

  @tag vhost: @test_vhost
  test "run: on an active node, trace_on command works on named vhost", context do
    assert TraceOnCommand.run([], context[:opts]) == :ok
  end

  @tag vhost: "toast"
  test "run: Turning tracing off on invalid host returns successfully", context do
    assert TraceOnCommand.run([], context[:opts]) == :ok
  end

  @tag vhost: @default_vhost
  test "banner", context do
    assert TraceOnCommand.banner([], context[:opts])
      =~ ~r/Starting tracing for vhost "#{context[:vhost]}" .../
  end
end
