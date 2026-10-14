import { encodeTimeBoundSetupURI, decodeSettingsFromSetupURI } from "@vrtmrz/livesync-commonlib/setup-uri";
import { DEFAULT_SETTINGS } from "@vrtmrz/livesync-commonlib/compat/common/types";

function parseArgs() {
  const a = {};
  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    const k = args[i];
    if (k === "--dbname") a.dbname = args[++i];
    else if (k === "--passphrase") a.passphrase = args[++i];
    else if (k === "--couchdb-uri") a.couchdbUri = args[++i];
    else if (k === "--couchdb-user") a.couchdbUser = args[++i];
    else if (k === "--couchdb-password") a.couchdbPassword = args[++i];
  }
  return a;
}

const args = parseArgs();
for (const r of ["dbname", "passphrase", "couchdbUri", "couchdbUser", "couchdbPassword"]) {
  if (!args[r]) {
    console.error(`Missing --${r}`);
    process.exit(1);
  }
}

const settings = {
  ...DEFAULT_SETTINGS,
  couchDB_URI: args.couchdbUri,
  couchDB_USER: args.couchdbUser,
  couchDB_PASSWORD: args.couchdbPassword,
  couchDB_DBNAME: args.dbname,
  remoteType: "",
  encrypt: true,
  passphrase: args.passphrase,
  usePluginSync: false,
  usePluginSyncV2: true,
  liveSync: true,
  syncOnSave: true,
  syncOnStart: true,
  isConfigured: true,
};

const result = await encodeTimeBoundSetupURI(settings, args.passphrase, {
  mode: "persistent",
  removeProperties: ["pluginSyncExtendedSetting"],
  skipDefaultValue: true,
});

const decoded = await decodeSettingsFromSetupURI(result.uri, args.passphrase);
if (!decoded || decoded.couchDB_DBNAME !== args.dbname || decoded.encrypt !== true || decoded.passphrase !== args.passphrase) {
  console.error("ROUND-TRIP CHECK FAILED");
  process.exit(1);
}

process.stdout.write(result.uri + "\n");
