// Maps Next.js static-export URLs (built with trailingSlash: true) onto their
// S3 object keys, e.g. /about -> /about/index.html, / -> /index.html.
// Requests for real files (containing a ".", e.g. /logo.jpg, /_next/static/x.js)
// pass through unchanged.
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  if (uri.endsWith("/")) {
    request.uri = uri + "index.html";
  } else if (!uri.includes(".")) {
    request.uri = uri + "/index.html";
  }

  return request;
}
