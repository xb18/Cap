import os
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName("org.freedesktop.portal.Desktop", bus)
requests = []


class Request(dbus.service.Object):
    @dbus.service.signal("org.freedesktop.portal.Request", signature="ua{sv}")
    def Response(self, response, results):
        pass

    @dbus.service.method("org.freedesktop.portal.Request")
    def Close(self):
        pass


def request_path(sender, options):
    token = str(options.get("handle_token", "t"))
    return "/org/freedesktop/portal/desktop/request/%s/%s" % (
        sender[1:].replace(".", "_"),
        token,
    )


class Portal(dbus.service.Object):
    @dbus.service.method(
        "org.freedesktop.portal.FileChooser",
        in_signature="ssa{sv}",
        out_signature="o",
        sender_keyword="sender",
    )
    def SaveFile(self, parent, title, options, sender=None):
        path = request_path(sender, options)
        request = Request(bus, path)
        requests.append(request)
        target = os.path.join(out, str(options.get("current_name", "saved")))
        print("SaveFile", repr(str(title)), target, flush=True)

        def answer():
            request.Response(
                dbus.UInt32(0),
                {"uris": dbus.Array(["file://" + target], signature="s")},
            )
            return False

        GLib.timeout_add(400, answer)
        return dbus.ObjectPath(path)

    @dbus.service.method(
        "org.freedesktop.portal.FileChooser",
        in_signature="ssa{sv}",
        out_signature="o",
        sender_keyword="sender",
    )
    def OpenFile(self, parent, title, options, sender=None):
        path = request_path(sender, options)
        request = Request(bus, path)
        requests.append(request)
        GLib.timeout_add(400, lambda: (request.Response(dbus.UInt32(1), {}), False)[1])
        return dbus.ObjectPath(path)

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        return dbus.UInt32(4)

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return {"version": dbus.UInt32(4)}


Portal(bus, "/org/freedesktop/portal/desktop")
print("portal ready", flush=True)
GLib.MainLoop().run()
