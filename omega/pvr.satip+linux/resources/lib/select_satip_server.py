#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import glob
import os
import socket
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

import xbmc
import xbmcaddon
import xbmcgui
import xbmcvfs


ADDON_ID = "pvr.satip"
SATIP_ST = "urn:ses-com:device:SatIPServer:1"
SATIP_SERVICE_ST = "urn:ses-com:service:SatIP:1"
ROOT_DEVICE_ST = "upnp:rootdevice"
SSDP_SEARCH_TARGETS = [SATIP_ST, SATIP_SERVICE_ST, ROOT_DEVICE_ST]
SSDP_MULTICAST_IP = "239.255.255.250"
SSDP_MULTICAST_PORT = 1900
DEFAULT_DISCOVERY_TIMEOUT_MS = 3000
DEFAULT_DISCOVERY_MX = 2
SOCKET_READ_STEP_SECONDS = 0.25
DEVICE_DESC_TIMEOUT_SECONDS = 2.5
MIN_DISCOVERY_TIMEOUT_MS = 500
MULTICAST_TTL = 2
USER_AGENT = "Kodi-pvr.satip-server-select/1.0"
INSTANCE_SETTINGS_GLOB = "special://userdata/addon_data/pvr.satip/instance-settings-*.xml"
INSTANCE_SETTINGS_DIR = "special://userdata/addon_data/pvr.satip"
DEFAULT_INSTANCE_SETTINGS_FILE = "instance-settings-1.xml"
INSTANCE_SETTINGS_SCHEMA = f"special://home/addons/{ADDON_ID}/resources/instance-settings.xml"
SETTING_ID_SATIP_SERVER_HOST = "satipServerHost"
SETTING_ID_SATIP_SELECT_SERVER_ACTION = "satipSelectServerAction"
KODI_INSTANCE_NAME_SETTING_ID = "kodi_addon_instance_name"
KODI_INSTANCE_ENABLED_SETTING_ID = "kodi_addon_instance_enabled"
DEFAULT_INSTANCE_NAME = "Migrated Add-on Config"


def _addon():
    return xbmcaddon.Addon(ADDON_ID)


def _label(label_id: int) -> str:
    text = _addon().getLocalizedString(label_id)
    return text if text else str(label_id)


def _log(message: str, level=xbmc.LOGINFO) -> None:
    xbmc.log(f"{ADDON_ID}: {message}", level)


def _instance_settings_files() -> list:
    translated = xbmcvfs.translatePath(INSTANCE_SETTINGS_GLOB)
    return sorted(glob.glob(translated))


def _default_instance_settings_path() -> str:
    directory = xbmcvfs.translatePath(INSTANCE_SETTINGS_DIR)
    return os.path.join(directory, DEFAULT_INSTANCE_SETTINGS_FILE)


def _load_schema_defaults() -> list:
    schema_path = xbmcvfs.translatePath(INSTANCE_SETTINGS_SCHEMA)
    tree = ET.parse(schema_path)
    root = tree.getroot()
    defaults = []
    for setting_node in root.findall(".//setting"):
        setting_id = setting_node.get("id", "").strip()
        if not setting_id:
            continue
        default_node = setting_node.find("./default")
        default_value = ""
        if default_node is not None and default_node.text is not None:
            default_value = default_node.text
        defaults.append((setting_id, default_value))
    return defaults


def _ensure_instance_settings_file() -> str:
    existing_files = _instance_settings_files()
    if existing_files:
        return existing_files[0]

    settings_dir = xbmcvfs.translatePath(INSTANCE_SETTINGS_DIR)
    try:
        os.makedirs(settings_dir, exist_ok=True)
        root = ET.Element("settings", {"version": "2"})

        instance_name_node = ET.SubElement(root, "setting", {"id": KODI_INSTANCE_NAME_SETTING_ID})
        instance_name_node.text = DEFAULT_INSTANCE_NAME

        instance_enabled_node = ET.SubElement(
            root,
            "setting",
            {"id": KODI_INSTANCE_ENABLED_SETTING_ID, "default": "true"},
        )
        instance_enabled_node.text = "true"

        for setting_id, default_value in _load_schema_defaults():
            setting_attributes = {"id": setting_id, "default": "true"}
            setting_node = ET.SubElement(root, "setting", setting_attributes)
            setting_node.text = default_value

        output_path = _default_instance_settings_path()
        ET.ElementTree(root).write(output_path, encoding="utf-8", xml_declaration=False)
        _log(f"created instance settings file {output_path}", xbmc.LOGINFO)
        return output_path
    except Exception as exc:
        _log(f"failed to create instance settings file: {exc}", xbmc.LOGERROR)
        return ""


def _read_current_host_from_instance_settings() -> str:
    for settings_path in _instance_settings_files():
        try:
            tree = ET.parse(settings_path)
        except Exception as exc:
            _log(f"failed to parse instance settings file {settings_path}: {exc}", xbmc.LOGDEBUG)
            continue

        root = tree.getroot()
        for setting_node in root.findall("./setting"):
            if setting_node.get("id", "") != SETTING_ID_SATIP_SERVER_HOST:
                continue
            return (setting_node.text or "").strip()
    return ""


def _write_setting_to_instance_settings(setting_id: str, setting_value: str) -> bool:
    if not setting_id:
        return False

    if setting_value is None:
        return False

    settings_path = _ensure_instance_settings_file()
    settings_files = [settings_path] if settings_path else []
    if not settings_files:
        return False

    for settings_path in settings_files:
        try:
            tree = ET.parse(settings_path)
        except Exception as exc:
            _log(f"failed to parse instance settings file {settings_path}: {exc}", xbmc.LOGDEBUG)
            continue

        root = tree.getroot()
        target_node = None
        for setting_node in root.findall("./setting"):
            if setting_node.get("id", "") == setting_id:
                target_node = setting_node
                break

        if target_node is None:
            target_node = ET.SubElement(root, "setting", {"id": setting_id})

        target_node.text = setting_value
        target_node.set("default", "false")

        try:
            tree.write(settings_path, encoding="utf-8", xml_declaration=False)
            _log(f"wrote instance setting {setting_id} to {settings_path}: {setting_value}", xbmc.LOGINFO)
            return True
        except Exception as exc:
            _log(f"failed to write instance settings file {settings_path}: {exc}", xbmc.LOGDEBUG)

    return False


def _write_host_to_instance_settings(selected_host: str) -> bool:
    host_written = _write_setting_to_instance_settings(SETTING_ID_SATIP_SERVER_HOST, selected_host)
    display_written = _write_setting_to_instance_settings(SETTING_ID_SATIP_SELECT_SERVER_ACTION, selected_host)
    return host_written and display_written


def _read_header_value(response_text: str, header_name: str) -> str:
    header_name_lower = header_name.lower() + ":"
    for raw_line in response_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.lower().startswith(header_name_lower):
            return line.split(":", 1)[1].strip()
    return ""


def _fetch_device_description(location_url: str) -> dict:
    metadata = {"friendly_name": "", "model_name": "", "is_satip": False}
    if not location_url:
        return metadata

    request = urllib.request.Request(location_url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=DEVICE_DESC_TIMEOUT_SECONDS) as response:
            data = response.read()
    except Exception as exc:
        _log(f"device description fetch failed for {location_url}: {exc}", xbmc.LOGDEBUG)
        return metadata

    try:
        root = ET.fromstring(data)
    except Exception as exc:
        _log(f"device description parse failed for {location_url}: {exc}", xbmc.LOGDEBUG)
        return metadata

    def local_name(tag_value: str) -> str:
        return tag_value.split("}", 1)[1] if "}" in tag_value else tag_value

    def find_first(node: ET.Element, wanted_tag: str):
        for candidate in node.iter():
            if local_name(candidate.tag).lower() == wanted_tag.lower():
                return candidate
        return None

    def find_text(node: ET.Element, wanted_tag: str) -> str:
        found = find_first(node, wanted_tag)
        if found is None or found.text is None:
            return ""
        return found.text.strip()

    def is_satip_device(device_node: ET.Element) -> bool:
        device_type = find_text(device_node, "deviceType").lower()
        if SATIP_ST.lower() in device_type:
            return True

        for child in device_node.iter():
            name = local_name(child.tag).lower()
            if name in ("x_satipcap", "x_satipm3u"):
                return True
        return False

    satip_device = None
    for device in root.iter():
        if local_name(device.tag).lower() != "device":
            continue
        if is_satip_device(device):
            satip_device = device
            break

    if satip_device is None:
        return metadata

    metadata["friendly_name"] = find_text(satip_device, "friendlyName")
    metadata["model_name"] = find_text(satip_device, "modelName")
    metadata["is_satip"] = True
    return metadata


def _build_ssdp_requests(mx_seconds: int) -> list:
    requests = []
    for search_target in SSDP_SEARCH_TARGETS:
        request = (
            "M-SEARCH * HTTP/1.1\r\n"
            f"HOST: {SSDP_MULTICAST_IP}:{SSDP_MULTICAST_PORT}\r\n"
            "MAN: \"ssdp:discover\"\r\n"
            f"MX: {mx_seconds}\r\n"
            f"ST: {search_target}\r\n"
            "\r\n"
        ).encode("utf-8")
        requests.append(request)
    return requests


def _is_discoverable_ipv4(local_ip: str) -> bool:
    if not local_ip:
        return False
    if local_ip == "0.0.0.0":
        return False
    if local_ip.startswith("127."):
        return False
    if local_ip.startswith("169.254."):
        return False
    return True


def _enumerate_ipv4_interfaces() -> list:
    candidates = set()
    try:
        infos = socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET, socket.SOCK_DGRAM)
        for info in infos:
            address = info[4][0] if info and len(info) >= 5 and info[4] else ""
            if _is_discoverable_ipv4(address):
                candidates.add(address)
    except Exception as exc:
        _log(f"getaddrinfo failed: {exc}", xbmc.LOGDEBUG)

    preferred_ip = ""
    try:
        route_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        route_socket.connect(("8.8.8.8", 80))
        preferred_ip = route_socket.getsockname()[0]
        route_socket.close()
    except Exception:
        preferred_ip = ""

    if _is_discoverable_ipv4(preferred_ip):
        ordered = [preferred_ip]
        ordered.extend(sorted(ip for ip in candidates if ip != preferred_ip))
        return ordered

    return sorted(candidates)


def _discover_on_interface(local_ip: str, requests: list, timeout_ms: int) -> list:
    responses = []
    end_time = time.time() + (max(timeout_ms, MIN_DISCOVERY_TIMEOUT_MS) / 1000.0)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    try:
        sock.bind((local_ip, 0))
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, MULTICAST_TTL)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(local_ip))
        sock.settimeout(SOCKET_READ_STEP_SECONDS)

        for request in requests:
            sock.sendto(request, (SSDP_MULTICAST_IP, SSDP_MULTICAST_PORT))

        while time.time() < end_time:
            try:
                data, source = sock.recvfrom(8192)
            except socket.timeout:
                continue
            except Exception as exc:
                _log(f"discovery receive failed on {local_ip}: {exc}", xbmc.LOGDEBUG)
                continue

            try:
                response_text = data.decode("utf-8", "ignore")
            except Exception:
                continue

            responses.append((response_text, source))
    except Exception as exc:
        _log(f"interface {local_ip} discovery failed: {exc}", xbmc.LOGDEBUG)
    finally:
        sock.close()

    return responses


def _build_display_name(server: dict) -> str:
    display = server.get("friendly_name") or server.get("model_name") or server.get("host") or server.get("location")
    host = server.get("host") or ""
    if host and display != host:
        display = f"{display} [{host}]"
    return display


def _show_selection_dialog(servers: list) -> int:
    current_host = _read_current_host_from_instance_settings()
    if not current_host:
        current_host = _addon().getSetting("satipServerHost").strip()
    heading = _label(30927)
    entries = []
    entry_indices = []
    preselect_index = -1
    current_found = False

    for index, server in enumerate(servers):
        display_name = _build_display_name(server)
        if current_host and server.get("host", "").strip().lower() == current_host.lower():
            current_found = True
            preselect_index = len(entries)
            display_name = f"{_label(30933)}: {display_name}"
        entries.append(display_name)
        entry_indices.append(index)

    if current_host and not current_found:
        entries.insert(0, _label(30932).format(host=current_host))
        entry_indices.insert(0, -1)
        preselect_index = 0

    try:
        selected_entry = xbmcgui.Dialog().select(heading, entries, preselect=preselect_index)
    except TypeError:
        selected_entry = xbmcgui.Dialog().select(heading, entries)

    if selected_entry < 0 or selected_entry >= len(entry_indices):
        return -1
    return entry_indices[selected_entry]


def _notify_selected(host: str) -> None:
    message = _label(30929).format(host=host)
    xbmcgui.Dialog().ok(_label(30927), message)
    xbmcgui.Dialog().notification(_label(30927), message, xbmcgui.NOTIFICATION_INFO, 4000)


def _notify_not_found() -> None:
    _log("no SAT>IP server discovered")
    xbmcgui.Dialog().ok(_label(30927), _label(30928))


def _create_progress_dialog():
    progress = xbmcgui.DialogProgress()
    progress.create(_label(30927), _label(30930))
    return progress


def _update_progress(progress_dialog, percent: int, interface_ip: str) -> bool:
    if progress_dialog is None:
        return True
    line1 = _label(30930)
    line2 = _label(30931).format(iface=interface_ip)
    progress_dialog.update(max(0, min(100, percent)), f"{line1}\n{line2}")
    if progress_dialog.iscanceled():
        _log("SAT>IP discovery cancelled by user")
        return False
    return True


def _discover_satip_servers(timeout_ms: int, mx_seconds: int, progress_dialog=None) -> list:
    requests = _build_ssdp_requests(mx_seconds)
    local_interfaces = _enumerate_ipv4_interfaces()
    _log(f"discovery interfaces: {', '.join(local_interfaces) if local_interfaces else '<none>'}", xbmc.LOGINFO)

    dedupe_by_location = {}
    total_interfaces = max(1, len(local_interfaces))
    for index, local_ip in enumerate(local_interfaces):
        step_percent = int((index * 100) / total_interfaces)
        if not _update_progress(progress_dialog, step_percent, local_ip):
            return []
        responses = _discover_on_interface(local_ip, requests, timeout_ms)
        _log(f"SSDP responses on {local_ip}: {len(responses)}", xbmc.LOGDEBUG)

        for response_text, source in responses:
            location_value = _read_header_value(response_text, "LOCATION")
            server_value = _read_header_value(response_text, "SERVER")
            if not location_value:
                continue

            parsed = urllib.parse.urlparse(location_value)
            host = parsed.hostname or source[0]
            if not host:
                continue

            location_key = location_value.lower().strip()
            if location_key in dedupe_by_location:
                continue

            dedupe_by_location[location_key] = {
                "host": host.strip(),
                "location": location_value.strip(),
                "server_header": server_value.strip(),
                "friendly_name": "",
                "model_name": "",
            }

    satip_servers = []
    for entry in dedupe_by_location.values():
        metadata = _fetch_device_description(entry["location"])
        if not metadata.get("is_satip", False):
            continue
        entry["friendly_name"] = metadata["friendly_name"]
        entry["model_name"] = metadata["model_name"]
        satip_servers.append(entry)
        _log(
            f"discovered SAT>IP server host={entry['host']} location={entry['location']} "
            f"friendly={entry['friendly_name']} model={entry['model_name']}",
            xbmc.LOGDEBUG,
        )

    satip_servers.sort(key=lambda item: (item["friendly_name"] or item["model_name"] or item["host"]).lower())
    return satip_servers


def run() -> None:
    timeout_ms = DEFAULT_DISCOVERY_TIMEOUT_MS
    mx_seconds = DEFAULT_DISCOVERY_MX
    _log(f"starting SAT>IP server discovery timeout_ms={timeout_ms} mx={mx_seconds}")

    progress = _create_progress_dialog()
    try:
        servers = _discover_satip_servers(timeout_ms, mx_seconds, progress)
    finally:
        progress.close()
    if not servers:
        _notify_not_found()
        return

    selected_index = _show_selection_dialog(servers)
    if selected_index < 0 or selected_index >= len(servers):
        _log("server selection cancelled by user")
        return

    selected_host = servers[selected_index].get("host", "").strip()
    if not selected_host:
        return
    host_written = _write_host_to_instance_settings(selected_host)
    if not host_written:
        xbmcgui.Dialog().ok(_label(30927), _label(30934))
        _log("failed to persist selected SAT>IP server host", xbmc.LOGERROR)
        return
    _log(f"selected SAT>IP server host={selected_host}")
    _notify_selected(selected_host)


if __name__ == "__main__":
    run()
