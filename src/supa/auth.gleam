// API page list best all the endpoints https://supabase.com/dashboard/project/wrdiolbafudgmcgvqhnb/api?page=users
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/string
import midas/task as t
import snag
import supa/client
import supa/utils

fn base(client) {
  let client.Client(host, key) = client
  request.new()
  |> request.set_host(host)
  |> request.prepend_header("apikey", key)
  |> request.set_path("/auth/v1")
  // Authorization header needed for auth endpoint
  |> request.prepend_header("Authorization", "Bearer " <> key)
  |> request.set_body(<<>>)
}

pub fn sign_in_with_otp(client, email_address, create_user) {
  let request =
    base(client)
    |> request.set_method(http.Post)
    |> utils.append_path("/otp")
    |> request.set_body(<<
      json.to_string(
        json.object([
          #("email", json.string(email_address)),
          #("create_user", json.bool(create_user)),
        ]),
      ):utf8,
    >>)
  use response <- t.do(t.fetch(request))
  decode_response(response, decode.success(Nil))
}

pub fn verify_otp(client, email_address, token) {
  let request =
    base(client)
    |> request.set_method(http.Post)
    |> utils.append_path("/verify")
    |> request.set_body(<<
      json.to_string(
        json.object([
          #("email", json.string(email_address)),
          #("token", json.string(token)),
          #("type", json.string("magiclink")),
        ]),
      ):utf8,
    >>)
  use response <- t.do(t.fetch(request))
  decode_response(response, verify_decoder())
}

pub fn verify_decoder() {
  use session <- decode.then(session_decoder())
  use user <- decode.field("user", user_decoder())
  decode.success(#(session, user))
}

// useful for storage
pub fn verify_to_json(session, user) {
  let User(created_at, email, id) = user
  let user =
    json.object([
      #("created_at", json.string(created_at)),
      #("email", json.string(email)),
      #("id", json.string(id)),
    ])
  let Session(access_token, expires_at, expires_in, refresh_token, token_type) =
    session
  json.object([
    #("access_token", json.string(access_token)),
    #("expires_at", json.int(expires_at)),
    #("expires_in", json.int(expires_in)),
    #("refresh_token", json.string(refresh_token)),
    #("token_type", json.string(token_type)),
    #("user", user),
  ])
}

pub type Session {
  Session(
    access_token: String,
    expires_at: Int,
    expires_in: Int,
    refresh_token: String,
    token_type: String,
  )
}

fn session_decoder() {
  use access_token <- decode.field("access_token", decode.string)
  use expires_at <- decode.field("expires_at", decode.int)
  use expires_in <- decode.field("expires_in", decode.int)
  use refresh_token <- decode.field("refresh_token", decode.string)
  use token_type <- decode.field("token_type", decode.string)
  decode.success(Session(
    access_token:,
    expires_at:,
    expires_in:,
    refresh_token:,
    token_type:,
  ))
}

pub type User {
  User(created_at: String, email: String, id: String)
}

fn user_decoder() {
  use created_at <- decode.field("created_at", decode.string)
  use email <- decode.field("email", decode.string)
  use id <- decode.field("id", decode.string)
  decode.success(User(created_at: created_at, email: email, id: id))
}

fn decode_response(response: response.Response(_), decoder) {
  case response.status {
    200 ->
      case json.parse_bits(response.body, decoder) {
        Ok(data) -> t.done(data)
        Error(reason) -> t.abort(snag.new(string.inspect(reason)))
      }
    _ ->
      case json.parse_bits(response.body, error_decoder()) {
        Ok(reason) -> t.abort(snag.new(reason.message))
        Error(reason) -> t.abort(snag.new(string.inspect(reason)))
      }
  }
}

pub type Reason {
  Reason(error: String, message: String)
}

fn error_decoder() {
  use error <- decode.field("error_code", decode.string)
  use message <- decode.field("msg", decode.string)
  decode.success(Reason(error:, message:))
}
