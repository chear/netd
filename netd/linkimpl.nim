import netd/iproute, netd/netlink
import conf/ast
import tables, strutils, sequtils, os

proc getRename*(identifier: string, suite: Suite): InterfaceName =
  let newName = suite.singleValue("name", required=false).stringValue
  let namespace = suite.singleValue("namespace", required=false).stringValue
  let name = if newName != nil: newName else: identifier
  return (namespace: namespace.nsNilToRoot, name: name)

proc applyRename(interfaceName: InterfaceName, target: InterfaceName) =
  let isAlreadyOk = (target.namespace == interfaceName.namespace) and (target.name == interfaceName.name)
  if not isAlreadyOk:
    rename(interfaceName, target.name, target.namespace)

proc applyRename(interfaceName: InterfaceName, suite: Suite): InterfaceName =
  result = getRename(interfaceName.name, suite)
  applyRename(interfaceName, result)

proc readAliasProperties(ifaceName: InterfaceName): Table[string, string] =
  result = initTable[string, string]()
  let data = ifaceName.getLinkAlias
  if data != nil and data.startsWith("NETD,"):
    let parts = data.split(",")
    for i, part in parts:
      if i == 0:
        continue
      let split = part.find('=')
      if split != -1:
        result[part[0..split-1]] = part[split+1..^1]

proc writeAliasProperties(ifaceName: InterfaceName, prop: Table[string, string]) =
  var s = "NETD"
  for k, v in prop:
    s.add("," & k & "=" & v)
  ipLinkSet(ifaceName, {"alias": s})

proc infoAboutLivingInterface(ifaceName: InterfaceName): LivingInterface =
  result.kernelName = ifaceName.name
  result.namespaceName = ifaceName.namespace

  let props = readAliasProperties(ifaceName)
  result.abstractName = props.getOrDefault("abstractName")
  result.isSynthetic = props.getOrDefault("isSynthetic") == "true"

proc listLivingInterfaces*(self: LinkManager): seq[LivingInterface] =
  if self.livingInterfacesCache == nil:
    self.livingInterfacesCache = @[]
    for name in listKernelInterfaces():
      self.livingInterfacesCache.add infoAboutLivingInterface(name)

  return self.livingInterfacesCache

proc invalidateInterfaceCache(self: LinkManager) =
  self.livingInterfacesCache = nil

proc findLivingInterface(interfaces: seq[LivingInterface], abstractName: string): Option[InterfaceName] =
  for candidate in interfaces:
    if candidate.abstractName == abstractName:
      return some(candidate.interfaceName)

  return none(InterfaceName)

proc removeUnusedInterfaces(self: LinkManager, managed: seq[ManagedInterface]) =
  let allInterfaces = listLivingInterfaces(self)
  var managedNames = initCountTable[string]()

  for iface in managed:
    echo "ManagedInterface $1" % $iface
    managedNames.inc iface.abstractName

  for iface in allInterfaces:
    if iface.isSynthetic and managedNames.getOrDefault(iface.abstractName) == 0:
      echo iface.abstractName, " is no longer managed"
      # check if still exists, deleting one side of veth might have deleted other
      if linkExists(iface.interfaceName):
        if getNlLink(iface.interfaceName).kind == nil:
          # probably wireless interface
          iwLinkDel(iface.interfaceName)
        else:
          ipLinkDel(iface.interfaceName)

proc setupNamespaces(self: LinkManager) =
  createDir("/var/run/netns")
  let namespaces = listNamespaces()
  echo "existing network namespaces: ", $namespaces
  if "root" notin namespaces:
    createRootNamespace()

  for cmd in self.manager.config.commandsWithName("namespace"):
    let nsname = cmd.args.unpackSeq1.stringValue.nsNilToRoot
    if nsname notin namespaces:
      ipNetnsCreate(nsname)
    if nsname != "root":
      # FIXME: race condition
      let loopback = (nsname, "lo")
      ipAddrFlush(loopback)
      ipAddrAdd(loopback, "127.0.0.1/8")
      ipAddrAdd(loopback, "::1/128")
      ipLinkUp(loopback)

proc gatherInterfacesAll(self: LinkManager): seq[ManagedInterface] =
  result = @[]
  for plugin in self.manager.iterPlugins:
    result &= plugin.gatherInterfaces()

method reload(self: LinkManager) =
  echo "reloading LinkManager"
  self.setupNamespaces()

  self.invalidateInterfaceCache()
  let managedInterfaces = self.gatherInterfacesAll()
  echo "managed interfaces: ", $managedInterfaces
  self.removeUnusedInterfaces(managedInterfaces)

  self.invalidateInterfaceCache()
  self.callAllPlugins(beforeSetupInterfaces)

  self.invalidateInterfaceCache()
  self.callAllPlugins(setupInterfaces)

  self.invalidateInterfaceCache()
  self.callAllPlugins(afterSetupInterfaces)
