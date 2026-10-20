.pragma library

// Compatibility pattern adapted from Omamail's replacement-bar bridge:
// https://github.com/huacnlee/omamail/blob/72dbef469d38504e9af3b2fa059a2dc5f56feddf/ui/bar/Bridge.js
// One persistent service publishes detached snapshots and explicit actions, so
// widgets also work when a replacement bar provides no live service lookup.
// Station keeps the trusted bar's direct path; this API exposes no service QObject.
var active = null

function publish(readSnapshot, actions) {
    var allowed = actions || ({})
    var api = Object.freeze({
        snapshot: function() {
            return active === api ? readSnapshot() : null
        },
        call: function(name, args) {
            if (active !== api) return undefined
            var key = String(name || "")
            if (!Object.prototype.hasOwnProperty.call(allowed, key)) return undefined
            if (typeof allowed[key] !== "function") return undefined
            return allowed[key].apply(null, Array.isArray(args) ? args : [])
        }
    })
    active = api
    return api
}

function current() { return active }

// A retired service must not clear a replacement published during hot reload.
function clear(api) { if (active === api) active = null }
