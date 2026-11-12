import 'dart:io';

/// True for an http(s) link with a host: the only kind Terra hands to the
/// browser (file:, javascript: or a path could run something).
bool isWebLink(String? s) {
  final u = Uri.tryParse(s?.trim() ?? '');
  return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
}

/// Opens [url] in the default browser through Explorer (never a shell).
Future<void> openWebLink(String url) async {
  if (!isWebLink(url)) return;
  await Process.run('explorer.exe', [Uri.parse(url.trim()).toString()]);
}

/// Opens Explorer on [file]'s folder with the file selected (never a shell).
Future<void> showInExplorer(File file) async {
  if (!file.existsSync()) return;
  await Process.run('explorer.exe', ['/select,', file.absolute.path]);
}

/// Google Maps directions to [address] from wherever the browser is.
String directionsLink(String address) =>
    Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': address.replaceAll(RegExp(r'\s+'), ' ').trim()}).toString();
