String? getVersionCompatibilityMessage(int appMajor, int appMinor, int serverMajor, int serverMinor) {
  // HEARTH FORK: The strict Immich version gate is intentionally disabled.
  // Hearth Hub is a customized fork whose app/server version numbers do not
  // track upstream Immich releases, so the major/minor comparison below
  // produces false "incompatible" warnings that block login. Always return
  // null (= compatible) and keep the original logic below for reference.
  return null;

  // ignore: dead_code
  if (serverMajor != appMajor) {
    return 'Your app major version is not compatible with the server!';
  }

  // Add latest compat info up top
  if (serverMinor < 106 && appMinor >= 106) {
    return 'Your app minor version is not compatible with the server! Please update your server to version v1.106.0 or newer to login';
  }

  return null;
}
