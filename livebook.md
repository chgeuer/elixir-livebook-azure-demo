# Talking to Azure Storage and the ARM API - From Erlang

## Section

We'll be using the Elixir programming language, running on the Erlang virtual machine (BEAM), in a docker container, using Elixir's web framework Phoenix, in an application called "LiveBook" ([`livebook-dev/livebook`](https://github.com/livebook-dev/livebook), exposing Elixir through a notebook interface.

```bash
targetFolder=/mnt/c/Users/chgeuer/Desktop/storagedemo
mkdir "${targetFolder}"

cp "/mnt/c/Users/chgeuer/Videos/This Is Spinal Tap - These go to 11.mpg-KOO5S4vxi0o.mp4" "${targetFolder}/TheseGoToEleven.mp4"

docker run -p 8080:8080 --pull always -u "$(id -u):$(id -g)" -v "${targetFolder}:/data" "livebook/livebook"
```

## Just enough Elixir to understand the code

```elixir
12 - 5
```

The `-` operator is just an infix syntax for the `Kernel.-/2` function, i.e. the function with name `-` in the `Kernel` module, which takes 2 arguments (arity):

```elixir
Kernel.-(12, 5)
```

The `|>` (pipe) operator in Elixir pipes the left-hand value *as first argument* into the subsequent function call, i.e. `a |> f(b,c)` is equivalend to `f(a,b,c)`.

Those familiar with F# might see the similarity; the difference is that in F#, the piped argument becomes the last in the function call, i.e. `a |> f(b,c)` in F# is equivalend to `f(b,c,a)`, simply because all functions in F# only have a single argument, so that this is `f(b)(c)(a)`...

```elixir
12 |> Kernel.-(5)
```

```elixir
12
|> Kernel.-(5)
```

### Processes and actors

```elixir
self()
```

## Pull in the Azure SDK for Elixir/Erlang

The `Mix.install()` function locally installs a collection of software libraries. In this case:

* The `chgeuer/ex_microsoft_azure_storage` contains a REST client for the Azure storage APIs
* The `chgeuer/ex_microsoft_azure_management` package contains REST APIs for the ARM API
* The `chgeuer/ex_microsoft_azure_utils` are some helpers handling Azure AD communications

Running this command for the first time times a few minutes, as all the source code gets pulled
from Github, and all packages (and their dependencies) get compiled.

<!-- livebook:{"disable_formatting":true} -->

```elixir
sparse = fn (k,v) ->
  { k, github: "chgeuer/ex_microsoft_azure_management",
       sparse: "Microsoft.Azure.Management.#{v}",
       app: false
  }
end

Mix.install([
  {:azure_utils, github: "chgeuer/ex_microsoft_azure_utils", app: false},
  # sparse.(:arm_compute, "Compute"),
  sparse.(:arm_resources, "Resources"),
  sparse.(:arm_subscription, "Subscription"),
  sparse.(:arm_storage, "Storage"),
  {:azure_storage, github: "chgeuer/ex_microsoft_azure_storage", app: false}
])
```

The `alias` section is similar to `using` or import statements, as we can omit parts of the module names.

```elixir
alias Microsoft.Azure.ActiveDirectory.DeviceAuthenticator
alias Microsoft.Azure.ActiveDirectory.DeviceAuthenticator.Model.State
alias Microsoft.Azure.ActiveDirectory.DeviceAuthenticatorSupervisor
alias Microsoft.Azure.Storage
alias Microsoft.Azure.Storage.{Container, Blob, Queue, BlobStorage}
```

Store a bunch of ARM API versions in a map:

```elixir
api_version = %{
  :resource_groups => "2018-02-01",
  :subscription => "2016-06-01",
  :storage => "2018-02-01"
}
```

And let's start an additional token fetching process for the ARM API `management.azure.com`...

```elixir
{:ok, management_pid} =
  %State{
    resource: "https://management.azure.com/",
    tenant_id: "chgeuerfte.onmicrosoft.com",
    azure_environment: :azure_global
  }
  |> DeviceAuthenticatorSupervisor.start_link()
```

```elixir
management_pid
```

```elixir
Process.alive?(management_pid)
```

Many processes are already running on our VM

```elixir
:erlang.registered()
```

```elixir
#
# Check some process info
#
management_pid |> Process.info()
```

```elixir
#
# This process is waiting for messages to arrive
#
Process.info(management_pid)[:status]
```

```elixir
#
# We can look at it's internal state
#
:sys.get_state(management_pid)
```

```elixir
management_pid |> DeviceAuthenticator.get_stage()
```

Start the device code flow.

Go to the [microsoft.com/devicelogin](https://microsoft.com/devicelogin)

```elixir
alias Microsoft.Azure.ActiveDirectory.DeviceAuthenticator.Model.DeviceCodeResponse

#
# Note the pattern matching here, we get a rather complex structure back from 
# DeviceAuthenticator.get_device_code/1, but we only care about the user_code
#

{:ok, %DeviceCodeResponse{user_code: uc}} =
  management_pid
  |> DeviceAuthenticator.get_device_code()

"Use user code #{uc}"
```

```elixir
alias Microsoft.Azure.ActiveDirectory.DeviceAuthenticator.Model.TokenResponse

#
# Binding the management_token value using pattern matching
#
{:ok, %TokenResponse{access_token: management_token}} =
  management_pid
  |> DeviceAuthenticator.get_token()

management_token
```

```elixir
#
# Functional (LINQ-style) navigating through the structure
#

management_token =
  management_pid
  |> DeviceAuthenticator.get_token()
  |> elem(1)
  |> Map.get(:access_token)
```

```elixir
management_token
|> JOSE.JWT.peek()
|> Map.get(:fields)
|> Enum.map(fn {k, v} -> "#{k |> String.pad_trailing(12, " ")}: #{inspect(v)}" end)
|> Enum.join("\n")
|> IO.puts()
```

```elixir
IO.puts("https://jwt.ms/#access_token=#{management_token}")
```

Now let's create an HTTP client which has our access token:

```elixir
conn = management_token |> Microsoft.Azure.Management.Resources.Connection.new()
```

```elixir
alias Microsoft.Azure.Management.Subscription.Api.Subscriptions, as: SubscriptionMgmt

IO.puts("Calling the subscription_list, using API version #{api_version.subscription}")

subscriptions =
  conn
  |> SubscriptionMgmt.subscriptions_list(api_version.subscription)
  |> elem(1)
  |> Map.get(:value)

subscription_name = "chgeuer-work"

subscription_id =
  subscriptions
  |> Enum.filter(&(&1 |> Map.get(:displayName) == subscription_name))
  |> hd
  |> Map.get(:subscriptionId)
```

```elixir
alias Microsoft.Azure.Management.Storage.Api.StorageAccounts, as: StorageMgmt

{:ok, %{value: accounts}} =
  conn
  |> StorageMgmt.storage_accounts_list(api_version.storage, subscription_id)

accounts
```

```elixir
accounts
|> Enum.map(&(&1 |> Map.get(:name)))
```

## Storage access

### Starting a device authentication flow with Azure AD

This starts an Erlang process (an 'actor'), which handles the communication with Azure AD. The `#PID<xxx.yyy.zzz>` stuff you see is the Erlang process ID.

```elixir
{:ok, storage_pid} =
  %State{
    resource: "https://storage.azure.com/",
    tenant_id: "chgeuerfte.onmicrosoft.com",
    azure_environment: :azure_global
  }
  |> DeviceAuthenticatorSupervisor.start_link()
```

Next, we can send the process behind `storage_pid` a message to tell us the current stage:

```elixir
storage_pid
|> DeviceAuthenticator.get_stage()
```

And give us the device code with which we need to authenticate to AAD ([microsoft.com/devicelogin](https://microsoft.com/devicelogin))

```elixir
{:ok, %{user_code: storage_usercode}} =
  storage_pid
  |> DeviceAuthenticator.get_device_code()

storage_usercode
```

Now we should no longer be polling, but be in a constant state of refreshing:

```elixir
storage_pid
|> DeviceAuthenticator.get_stage()
```

```elixir
# storage_pid
# |> DeviceAuthenticator.force_refresh()
```

When we ask the process for the token, we get a response:

```elixir
storage_pid
|> DeviceAuthenticator.get_token()
```

... from which we can extract the token:

```elixir
{:ok, %{access_token: storage_token}} =
  storage_pid
  |> DeviceAuthenticator.get_token()

storage_token
|> JOSE.JWT.peek()
|> Map.get(:fields)
|> Enum.map(fn {k, v} ->
  "#{k |> String.pad_trailing(12, " ")}: #{inspect(v)}"
end)
|> Enum.join("\n")
|> IO.puts()

"https://jwt.ms/#access_token=#{storage_token}"
```

### Now let's talk to Azure Blob Storage

We're now using an input cell in this LiveBook to allow the user to specify the storage account name.

The `aad_token_provider` is a lambda function which, on each call, asks the process which keeps our storage token fresh, for the current access token.

```elixir
accounts
|> Enum.map(&(&1 |> Map.get(:name)))
|> IO.inspect(label: "Available storage accounts")

:ok
```

<!-- livebook:{"livebook_object":"cell_input","name":"Storage Account Name","type":"text","value":"bltcdn"} -->

```elixir
storage_account_name = IO.gets("Storage Account Name") |> String.trim()

IO.puts("We'll be using storage account '#{storage_account_name}'")

aad_token_provider = fn _resource ->
  storage_pid
  |> DeviceAuthenticator.get_token()
  |> elem(1)
  |> Map.get(:access_token)
end

storage = %Storage{
  account_name: storage_account_name,
  cloud_environment_suffix: "core.windows.net",
  aad_token_provider: aad_token_provider
}
```

### Set HTTP proxy

Given we're running in a Docker container on WSL2, we could still ask the SDK to funnel all outgoing calls through Fiddler on the Windows side.

```elixir
"http_proxy" |> System.put_env("192.168.1.10:8888")

# "http_proxy" |> System.delete_env()
```

### List storage containers

```elixir
{:ok, %{containers: containers}} =
  storage
  |> Container.list_containers()

containers
|> Enum.map(& &1.name)
```

### Create a new storage container

<!-- livebook:{"livebook_object":"cell_input","name":"Container Name","type":"text","value":"demop12"} -->

```elixir
container_name = IO.gets("Container Name") |> String.trim()

# storage
# |> Container.new(container_name)
# |> Container.create_container()
```

```elixir
storage
|> Container.new(container_name)
|> Container.set_container_acl_public_access_container()
```

```elixir
storage
|> Container.new(container_name)
|> Container.list_blobs()
```

```elixir
storage
|> Container.new(container_name)
|> Blob.upload_file("/data/TheseGoToEleven.mp4")
```

```elixir
{:ok, %{blobs: blobs}} =
  storage
  |> Container.new(container_name)
  |> Container.list_blobs()

blobs
|> Enum.map(&(&1 |> Map.get(:name)))
|> Enum.join("\n")
|> IO.puts()
```