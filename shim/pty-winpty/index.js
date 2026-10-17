'use strict'
/**
 * node-pty-compatible spawn() over winpty, for Windows 7 where ConPTY does not exist.
 *
 * Implements the IPty members DSH's subprocess-local uses: pid, onData, onExit, write,
 * resize, pause, resume, kill. winpty.dll is called through koffi (resolved by the
 * importer's dependencies; the desktop runtime hoists koffi); its agent
 * (bin\winpty-agent.exe) hosts a hidden console and scrapes it into VT output on a
 * named pipe, while input is written to a second, inbound-only pipe. Both pipes carry UTF-8.
 * The process is spawned with AUTO_SHUTDOWN | EXIT_AFTER_SHUTDOWN, so the agent drains
 * the output and closes CONOUT once the child exits; that close (or a process-handle
 * poll, as a fallback) ends the terminal and reports the exit code.
 */
const { EventEmitter } = require('node:events')
const fs = require('node:fs')
const net = require('node:net')
const path = require('node:path')

const WINPTY_FLAG_COLOR_ESCAPES = 0x4
const WINPTY_MOUSE_MODE_AUTO = 1
const WINPTY_SPAWN_FLAG_AUTO_SHUTDOWN = 0x1
const WINPTY_SPAWN_FLAG_EXIT_AFTER_SHUTDOWN = 0x2
const STILL_ACTIVE = 259
const EXIT_POLL_MS = 250

// Inside an Electron app.asar, binaries live under app.asar.unpacked: koffi's LoadLibraryW is not
// redirected the way require() of a .node file is. winpty.dll finds winpty-agent.exe beside itself.
const BIN = path.join(__dirname, 'bin').replace(/\.asar(?=[\\/])/u, '.asar.unpacked')

let bindings
function load() {
  if (bindings !== undefined) return bindings
  const koffi = require('koffi')
  const winpty = koffi.load(path.join(BIN, 'winpty.dll'))
  const kernel32 = koffi.load('kernel32.dll')
  bindings = {
    configNew: winpty.func('void *winpty_config_new(uint64_t flags, _Out_ void **err)'),
    configFree: winpty.func('void winpty_config_free(void *cfg)'),
    configSetInitialSize: winpty.func('void winpty_config_set_initial_size(void *cfg, int cols, int rows)'),
    configSetMouseMode: winpty.func('void winpty_config_set_mouse_mode(void *cfg, int mode)'),
    open: winpty.func('void *winpty_open(void *cfg, _Out_ void **err)'),
    coninName: winpty.func('str16 winpty_conin_name(void *wp)'),
    conoutName: winpty.func('str16 winpty_conout_name(void *wp)'),
    spawnConfigNew: winpty.func('void *winpty_spawn_config_new(uint64_t flags, str16 appname, str16 cmdline, str16 cwd, void *env, _Out_ void **err)'),
    spawnConfigFree: winpty.func('void winpty_spawn_config_free(void *cfg)'),
    spawn: winpty.func('int winpty_spawn(void *wp, void *cfg, _Out_ void **process, _Out_ void **thread, _Out_ uint32_t *createError, _Out_ void **err)'),
    setSize: winpty.func('int winpty_set_size(void *wp, int cols, int rows, _Out_ void **err)'),
    free: winpty.func('void winpty_free(void *wp)'),
    errorMsg: winpty.func('str16 winpty_error_msg(void *err)'),
    errorFree: winpty.func('void winpty_error_free(void *err)'),
    getProcessId: kernel32.func('uint32_t GetProcessId(void *process)'),
    getExitCodeProcess: kernel32.func('int GetExitCodeProcess(void *process, _Out_ uint32_t *code)'),
    closeHandle: kernel32.func('int CloseHandle(void *handle)'),
  }
  return bindings
}

/** Throw winpty's message for a failed call, freeing the error object either way. */
function checked(api, value, errSlot, call) {
  const err = errSlot[0]
  if (value) {
    if (err) api.errorFree(err)
    return value
  }
  const message = err ? api.errorMsg(err) : 'no error detail'
  if (err) api.errorFree(err)
  throw new Error(`winpty: ${call} failed: ${message}`)
}

/** Quote one argument for CommandLineToArgvW. */
function quoteArg(arg) {
  if (arg === '') return '""'
  if (!/[\s"]/u.test(arg)) return arg
  let quoted = '"'
  let backslashes = 0
  for (const ch of arg) {
    if (ch === '\\') { backslashes++; continue }
    if (ch === '"') quoted += '\\'.repeat(backslashes * 2 + 1) + '"'
    else quoted += '\\'.repeat(backslashes) + ch
    backslashes = 0
  }
  return quoted + '\\'.repeat(backslashes * 2) + '"'
}

/** CreateProcess-style UTF-16 environment block: NAME=VALUE entries, each NUL-terminated, then a final NUL. */
function environmentBlock(env) {
  const entries = Object.entries(env)
    .filter(([name, value]) => value !== undefined && name !== '' && !name.includes('='))
    .map(([name, value]) => `${name}=${value}`)
  return Buffer.from(`${entries.join('\0')}\0\0`, 'utf16le')
}

class WinptyTerminal {
  constructor(file, args, options) {
    const api = load()
    this.cols = options.cols ?? 80
    this.rows = options.rows ?? 24
    this.process = file
    this._api = api
    this._events = new EventEmitter()
    this._exited = false

    const configErr = [null]
    const config = checked(api, api.configNew(WINPTY_FLAG_COLOR_ESCAPES, configErr), configErr, 'winpty_config_new')
    try {
      api.configSetInitialSize(config, this.cols, this.rows)
      api.configSetMouseMode(config, WINPTY_MOUSE_MODE_AUTO)
      const openErr = [null]
      this._wp = checked(api, api.open(config, openErr), openErr, 'winpty_open')
    } finally {
      api.configFree(config)
    }

    try {
      const cmdline = [file, ...args].map(quoteArg).join(' ')
      const spawnConfigErr = [null]
      const spawnConfig = checked(api, api.spawnConfigNew(
        WINPTY_SPAWN_FLAG_AUTO_SHUTDOWN | WINPTY_SPAWN_FLAG_EXIT_AFTER_SHUTDOWN,
        file, cmdline, options.cwd ?? null, environmentBlock(options.env ?? process.env), spawnConfigErr,
      ), spawnConfigErr, 'winpty_spawn_config_new')
      const processSlot = [null]
      const threadSlot = [null]
      const createError = [0]
      const spawnErr = [null]
      let spawned
      try {
        spawned = api.spawn(this._wp, spawnConfig, processSlot, threadSlot, createError, spawnErr)
      } finally {
        api.spawnConfigFree(spawnConfig)
      }
      if (!spawned && createError[0] !== 0) {
        if (spawnErr[0]) api.errorFree(spawnErr[0])
        const error = new Error(`winpty: CreateProcess failed for ${file} (Win32 ${createError[0]})`)
        error.code = createError[0] === 2 || createError[0] === 3 ? 'ENOENT' : 'EWINPTY'
        throw error
      }
      checked(api, spawned, spawnErr, 'winpty_spawn')
      if (threadSlot[0]) api.closeHandle(threadSlot[0])
      this._processHandle = processSlot[0]
      this.pid = api.getProcessId(this._processHandle)
    } catch (error) {
      api.free(this._wp)
      this._wp = null
      throw error
    }

    // CONIN is an inbound-only pipe. net.connect falls back to a read-only handle for it, so it is
    // opened write-only through fs (CreateFileW with GENERIC_WRITE and OPEN_EXISTING) instead.
    this._input = fs.createWriteStream('', { fd: fs.openSync(api.coninName(this._wp), fs.constants.O_WRONLY) })
    this._output = net.connect(api.conoutName(this._wp))
    this._output.setEncoding('utf8')
    this._output.on('data', (data) => { this._events.emit('data', data) })
    this._output.on('close', () => { this._finish() })
    // Pipe errors surface as the terminal ending; the exit code comes from the process handle.
    this._input.on('error', () => {})
    this._output.on('error', () => {})
    // Fallback when CONOUT stays open after the child exits: give the agent a moment to drain, then end.
    this._poll = setInterval(() => {
      if (this._exitCode() === undefined) return
      clearInterval(this._poll)
      setTimeout(() => { this._finish() }, 500)
    }, EXIT_POLL_MS)
  }

  onData(listener) {
    this._events.on('data', listener)
    return { dispose: () => { this._events.off('data', listener) } }
  }

  onExit(listener) {
    this._events.on('exit', listener)
    return { dispose: () => { this._events.off('exit', listener) } }
  }

  write(data) {
    if (!this._exited) this._input.write(data)
  }

  resize(cols, rows) {
    if (this._exited) return
    const err = [null]
    checked(this._api, this._api.setSize(this._wp, cols, rows, err), err, 'winpty_set_size')
    this.cols = cols
    this.rows = rows
  }

  pause() { this._output.pause() }

  resume() { this._output.resume() }

  /** Close the winpty console, which terminates every process attached to it; the signal name is not mapped. */
  kill(_signal) {
    if (this._exited || this._wp === null) return
    this._api.free(this._wp)
    this._wp = null
  }

  _exitCode() {
    if (this._processHandle === null) return undefined
    const code = [0]
    if (!this._api.getExitCodeProcess(this._processHandle, code)) return undefined
    return code[0] === STILL_ACTIVE ? undefined : code[0]
  }

  _finish() {
    if (this._exited) return
    this._exited = true
    clearInterval(this._poll)
    const exitCode = this._exitCode() ?? 1
    this._api.closeHandle(this._processHandle)
    this._processHandle = null
    if (this._wp !== null) { this._api.free(this._wp); this._wp = null }
    this._input.destroy()
    this._output.destroy()
    this._events.emit('exit', { exitCode, signal: undefined })
  }
}

/**
 * Start file with args in a winpty console.
 * @param {string} file - executable path.
 * @param {string[]} args - arguments.
 * @param {{ cols?: number, rows?: number, cwd?: string, env?: Record<string, string | undefined>, name?: string }} options
 */
function spawn(file, args, options = {}) {
  return new WinptyTerminal(file, Array.isArray(args) ? args : [args], options)
}

module.exports = { spawn }
