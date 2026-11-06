/// The address of a Tracearr image (a poster or an avatar).
///
/// Tracearr hands images as paths on itself (`/api/v1/images/proxy?...`), never
/// as absolute URLs, and the models keep them as given. The caller supplies
/// [base], the address it actually reached Tracearr on (home or away, as the
/// connection's reach says): we never read the saved address here, so an image
/// follows the route the rest of the requests took.
///
/// The base's own path is kept, because Tracearr may live under a prefix
/// behind a reverse proxy (`https://host/tracearr`), and a plain
/// [Uri.resolve] of `/api/...` would drop it.
///
/// An absolute [relative] gives null. The credential travels in a header on
/// these requests, and we must not offer it to a host that is not the one the
/// user configured.
Uri? resolveTracearrImage(String? relative, Uri base) {
  final path = relative?.trim() ?? '';
  if (path.isEmpty) return null;
  if (Uri.tryParse(path)?.hasScheme ?? true) return null;
  // Protocol-relative (`//host/x`) is absolute too.
  if (path.startsWith('//')) return null;
  final prefix = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  final tail = path.startsWith('/') ? path : '/$path';
  final joined = Uri.tryParse('$prefix$tail');
  if (joined == null) return null;
  // Built, not `base.replace`: a replace with a null query keeps the base's.
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: joined.path,
    query: joined.hasQuery ? joined.query : null,
  );
}
