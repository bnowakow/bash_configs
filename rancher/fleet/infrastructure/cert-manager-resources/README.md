# cert-manager resources

Place the non-secret cert-manager resources managed by Fleet in this directory, for
example ClusterIssuers and test Certificates.

The Cloudflare API token must be supplied as a secret through a secret-management process
or applied separately. Do not commit the token to this directory.

The existing files in `../../../../cert-manager/` are retained as migration references for
now. They are not automatically included in this Fleet bundle.
