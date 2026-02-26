-- Default Aperture configuration.
--
-- This template produces a config that grants all tailnet identities
-- access to Anthropic models. Network-level ACLs (in your tailnet
-- policy) should restrict which devices can reach Aperture.
--
-- Customize the `src` lists, models, and webhook URL for your setup.

let T = ./types.dhall

let anthropicModels =
      [ "claude-sonnet-4-20250514"
      , "claude-haiku-4-5-20251001"
      , "claude-opus-4-20250514"
      ]

let adminGrant
    : T.TempGrant
    = { src = [ "*" ], grants = [ T.Grant.Role { role = "admin" } ] }

let userGrant
    : T.TempGrant
    = { src = [ "*" ]
      , grants =
        [ T.Grant.Role { role = "user" }
        , T.Grant.Providers
            { providers =
              [ { provider = "anthropic"
                , model = "claude-sonnet-4-20250514"
                }
              , { provider = "anthropic"
                , model = "claude-haiku-4-5-20251001"
                }
              , { provider = "anthropic"
                , model = "claude-opus-4-20250514"
                }
              ]
            }
        ]
      }

let webhookGrant
    : T.TempGrant
    = { src = [ "*" ]
      , grants =
        [ T.Grant.HookGrant
            { hook =
              { match =
                { providers = [ "*" ], models = [ "*" ], events = [ "tool_call_entire_request" ] }
              , hook = "rj-gateway"
              , fields = [ "tools", "request_body", "response_body" ]
              }
            }
        ]
      }

in  { temp_grants = [ adminGrant, userGrant, webhookGrant ]
    , providers = toMap
        { anthropic =
          { baseurl = "https://api.anthropic.com"
          , credential = "keyid:p:anthropic:sk-ant-a"
          , models = anthropicModels
          , authorization = "x-api-key"
          , compatibility = { anthropic_messages = True }
          }
        }
    , hooks = toMap
        { `rj-gateway` =
          { url = "https://rj-gateway.example.ts.net/aperture/webhook" }
        }
    }
