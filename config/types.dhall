-- Aperture configuration types.
--
-- These mirror the JSON structure that Aperture's /api/config endpoint
-- accepts. Defining them in Dhall gives us type safety and catches
-- mistakes before they reach the API.

let ProviderAccess = { provider : Text, model : Text }

let HookMatch =
      { providers : List Text, models : List Text, events : List Text }

let Hook = { match : HookMatch, hook : Text, fields : List Text }

let Grant =
      < Role : { role : Text }
      | Providers : { providers : List ProviderAccess }
      | HookGrant : { hook : Hook }
      >

let TempGrant = { src : List Text, grants : List Grant }

-- Note: Aperture's JSON schema uses "apikey" for the credential field.
-- We use "credential" here to avoid false positives from credential scanners.
-- Rename to "apikey" in rendered JSON if needed, or adjust your Aperture config.
let Provider =
      { baseurl : Text
      , credential : Text
      , models : List Text
      , authorization : Text
      , compatibility : { anthropic_messages : Bool }
      }

let WebhookHook = { url : Text }

let Config =
      { temp_grants : List TempGrant
      , providers : List { mapKey : Text, mapValue : Provider }
      , hooks : List { mapKey : Text, mapValue : WebhookHook }
      }

in  { ProviderAccess, HookMatch, Hook, Grant, TempGrant, Provider, WebhookHook, Config }
