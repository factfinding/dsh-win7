// Local stand-in for the dsh-win7 GitHub Releases, for testing Desktop auto-update in a VM.
// It serves <root>\<tag>\<file> with GitHub's observable behavior:
//   /releases/latest/download/<file>   302 -> /releases/download/<latest tag>/<file>
//   /releases/download/<tag>/<file>    302 -> /assets/<tag>/<file>
//   /assets/<tag>/<file>               200, or 206 for one byte range; several ranges get 501 like GitHub
// and logs every request, so a test can tell a differential download (range requests) from a full one.
// Usage: node win7-update-test-server.mjs <root> <latest tag> [listen address] [port]
import { createReadStream, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { join, normalize } from 'node:path'

const [root, latestTag, host = '0.0.0.0', port = '8817'] = process.argv.slice(2)
if (root === undefined || latestTag === undefined) {
  console.error('usage: node win7-update-test-server.mjs <root> <latest tag> [listen address] [port]')
  process.exit(2)
}

function log(request, status, detail = '') {
  const range = request.headers.range === undefined ? '' : ` range=${request.headers.range}`
  console.log(`${new Date().toISOString()} ${request.method} ${request.url}${range} -> ${status}${detail}`)
}

function redirect(request, response, location) {
  response.writeHead(302, { Location: location, 'Content-Length': '0' }).end()
  log(request, 302, ` ${location}`)
}

createServer((request, response) => {
  const path = decodeURIComponent(new URL(request.url, 'http://local').pathname)
  let match
  if ((match = /^\/releases\/latest\/download\/([^/]+)$/u.exec(path))) {
    return redirect(request, response, `/releases/download/${latestTag}/${match[1]}`)
  }
  if ((match = /^\/releases\/download\/([^/]+)\/([^/]+)$/u.exec(path))) {
    return redirect(request, response, `/assets/${match[1]}/${match[2]}`)
  }
  if (!(match = /^\/assets\/([^/]+)\/([^/]+)$/u.exec(path)) || match[1].includes('..') || match[2].includes('..')) {
    response.writeHead(404).end()
    return log(request, 404)
  }
  const file = normalize(join(root, match[1], match[2]))
  let size
  try { size = statSync(file).size } catch {
    response.writeHead(404).end()
    return log(request, 404)
  }
  const range = request.headers.range
  if (range !== undefined) {
    if (range.includes(',')) {
      response.writeHead(501, { 'Content-Type': 'text/plain' }).end('Unsupported client range')
      return log(request, 501)
    }
    const bytes = /^bytes=(\d+)-(\d*)$/u.exec(range)
    const start = bytes === null ? NaN : Number(bytes[1])
    const end = bytes === null ? NaN : bytes[2] === '' ? size - 1 : Math.min(Number(bytes[2]), size - 1)
    if (!(start <= end && end < size)) {
      response.writeHead(416, { 'Content-Range': `bytes */${size}` }).end()
      return log(request, 416)
    }
    response.writeHead(206, { 'Accept-Ranges': 'bytes', 'Content-Range': `bytes ${start}-${end}/${size}`,
      'Content-Length': String(end - start + 1), 'Content-Type': 'application/octet-stream' })
    log(request, 206, ` ${end - start + 1} bytes`)
    if (request.method === 'HEAD') return response.end()
    return createReadStream(file, { start, end }).pipe(response)
  }
  response.writeHead(200, { 'Accept-Ranges': 'bytes', 'Content-Length': String(size), 'Content-Type': 'application/octet-stream' })
  log(request, 200, ` ${size} bytes`)
  if (request.method === 'HEAD') return response.end()
  createReadStream(file).pipe(response)
}).listen(Number(port), host, () => { console.log(`serving ${root} on http://${host}:${port}/, latest tag ${latestTag}`) })
