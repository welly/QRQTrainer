// Nothing runs at start-up: the module is a WASI reactor and JavaScript calls the exports in
// Exports.swift. (Globals live there, not here, so they are initialised lazily rather than by main.)
