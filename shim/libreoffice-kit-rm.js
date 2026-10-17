import { chmod as dshChmod, readdir as dshReaddir } from "node:fs/promises";
/**
* [win7] Windows 7's shell creates a read-only Documents folder (with desktop.ini) under the helper's
* USERPROFILE, and RemoveDirectory refuses read-only directories. A recursive rm that fails with EPERM
* on Windows clears the read-only attribute across the tree and retries once; every other case is fs.rm.
*/
async function rm(path, options) {
	try {
		return await fsRm(path, options);
	} catch (error) {
		if (process.platform !== "win32" || error?.code !== "EPERM" || !options?.recursive) throw error;
		await dshClearReadOnly(path);
		return fsRm(path, options);
	}
}
async function dshClearReadOnly(path) {
	let entries;
	try {
		await dshChmod(path, 0o777);
		entries = await dshReaddir(path, { withFileTypes: true });
	} catch {
		// A path that vanished or is not a directory needs no attribute change; the retried rm reports real failures.
		return;
	}
	for (const entry of entries) {
		const child = `${path}\\${entry.name}`;
		if (entry.isDirectory()) await dshClearReadOnly(child);
		else await dshChmod(child, 0o666).catch(() => {});
	}
}
