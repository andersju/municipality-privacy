defmodule SiteGenerator.AddStuff do
  import SiteGenerator.Helpers
  import Sqlitex.{Query, Statement}

  def start do
    {:ok, db} = Sqlitex.open("data/crawl-data.sqlite")

    add_columns(db, "http_requests", ~w(base_domain scheme), "TEXT")
    add_columns(db, "http_response_cookies", ~w(baseDomain), "TEXT")
    add_columns(db, "site_visits",   ~w(municipality_name scheme hsts referrer_policy score), "TEXT")
    add_columns(db, "site_visits",   ~w(first_party_profile_cookies third_party_profile_cookies
                                        first_party_session_cookies third_party_session_cookies
                                        third_party_requests insecure_requests), "INTEGER")
    add_domain_meta(db)
    add_cookie_meta(db)
    update_sites(db)

    Sqlitex.close(db)
  end

  defp add_columns(db, table, columns_to_add, type) do
    existing_columns =
      db
      |> Sqlitex.query!("PRAGMA table_info(#{table})")
      |> MapSet.new(fn(x) -> x[:name] end)

    columns_to_add
    |> MapSet.new
    |> MapSet.difference(existing_columns)
    |> Enum.each(fn(column) ->
         IO.puts "Adding column #{column} #{type} to table #{table}"
         Sqlitex.exec(db, "ALTER TABLE #{table} ADD COLUMN #{column} #{type}")
       end)
  end

  # TODO: Let OpenWPM do this instead.
  defp add_domain_meta(db) do
    IO.puts "Setting base_domain and scheme in all rows in http_requests"
    db
    |> query!("SELECT id, url FROM http_requests")
    |> Enum.each(fn(x) ->
         scheme = URI.parse(x[:url]).scheme
         prepare!(db, "UPDATE http_requests SET base_domain = ?, scheme = ? WHERE id = ?")
         |> bind_values!([get_base_domain(x[:url]), scheme, x[:id]])
         |> exec!
       end)
  end

  # TODO: Let OpenWPM do this instead.
  defp add_cookie_meta(db) do
    IO.puts "Setting baseDomain in all rows in http_response_cookies"
    db
    |> query!("SELECT id, domain FROM http_response_cookies")
    |> Enum.each(fn(x) ->
         base_domain = x[:domain] |> String.replace_prefix(".", "") |> PublicSuffix.registrable_domain
         prepare!(db, "UPDATE http_response_cookies SET baseDomain = ? WHERE id = ?")
         |> bind_values!([base_domain, x[:id]])
         |> exec!
       end)
  end

  defp get_municipalities do
    "data/municipalities.txt"
    |> File.read!
    |> String.split("\n")
    |> List.delete("")
    |> Enum.reduce(%{}, fn(x), acc ->
         [url, name] = String.split(x, "|")
         base_name = get_base_domain(url)
         Map.put_new(acc, base_name, name)
       end)
  end

  defp update_sites(db) do
    municipalities = get_municipalities
    db
    |> query!("SELECT visit_id, site_url FROM site_visits")
    |> Enum.each(&(update_site(db, municipalities, &1)))
  end

  defp update_site(db, municipalities, [visit_id: visit_id, site_url: site_url]) do
    IO.puts "Updating site #{site_url} (visit_id #{visit_id})"

    base_domain                           = get_base_domain(site_url)
    scheme                                = URI.parse(site_url).scheme
    third_party_requests                  = get_third_party_requests(db, visit_id, base_domain)
    {insecure_requests, _secure_requests} = get_request_types(db, visit_id)
    referrer_policy                       = get_referrer_policy(site_url)
    headers                               = get_headers(db, visit_id)
    hsts_header                           = Map.get(headers, "strict-transport-security", 0)
    {profile_cookies_first, profile_cookies_third} = get_cookie_count(db, visit_id, base_domain)
    {session_cookies_first, session_cookies_third} = get_session_cookie_count(db, visit_id, base_domain)

    # It could be that the HSTS header is set but with value max-age=0, which
    # "signals the UA to cease regarding the host as a Known HSTS Host" (RFC 6797 6.1.1)
    # In that case, we set hsts to 0; otherwise we set the actual value.
    hsts =
      cond do
        hsts_header !== 0 && hsts_header =~ ~r/max-age=0/i -> 0
        true -> hsts_header
      end

    score =
      cond do
        scheme == "https" && profile_cookies_first == 0 && profile_cookies_third == 0
        && String.contains?(referrer_policy, ["no-referrer", "never"])
        && hsts !== 0 && third_party_requests == 0 && insecure_requests == 0
          -> "a"
        scheme == "https" && profile_cookies_third == 0 && third_party_requests == 0
        && insecure_requests == 0
          -> "b"
        (scheme == "https" && third_party_requests > 0 && insecure_requests == 0) || (third_party_requests == 0)
          -> "c"
        (scheme == "https" && insecure_requests) || (profile_cookies_third == 0)
          -> "d"
        true
          -> "e"
      end

    db
    |> prepare!(
         "UPDATE site_visits
          SET municipality_name = ?,
              scheme = ?,
              hsts = ?,
              first_party_profile_cookies = ?,
              third_party_profile_cookies = ?,
              first_party_session_cookies = ?,
              third_party_session_cookies = ?,
              third_party_requests = ?,
              insecure_requests = ?,
              referrer_policy = ?,
              score = ?
          WHERE visit_id = ?")
    |> bind_values!([municipalities[base_domain],
                     scheme,
                     hsts,
                     profile_cookies_first,
                     profile_cookies_third,
                     session_cookies_first,
                     session_cookies_third,
                     third_party_requests,
                     insecure_requests,
                     referrer_policy,
                     score,
                     visit_id])
    |> exec!
  end

  # Returns tuple with number of first-party cookies and number of
  # third-party cookies.
  defp get_cookie_count(db, visit_id, base_domain) do
    db
    |> prepare!("SELECT * FROM profile_cookies WHERE visit_id = ?")
    |> bind_values!([visit_id])
    |> fetch_all!
    |> Enum.partition(&(&1[:baseDomain] == base_domain))
    |> Tuple.to_list
    |> (&({Enum.count(List.first(&1)), Enum.count(List.last(&1))})).()
  end

  # Returns tuple with number of first-party session cookies and number
  # of third-party session cookies.
  defp get_session_cookie_count(db, visit_id, base_domain) do
    db
    |> prepare!("SELECT DISTINCT domain, name, baseDomain
                 FROM http_response_cookies
                 WHERE header_id IN
                  (SELECT id FROM http_responses WHERE visit_id = ?)
                 AND expires IS null")
    |> bind_values!([visit_id])
    |> fetch_all!
    |> Enum.partition(&(&1[:baseDomain] == base_domain))
    |> Tuple.to_list
    |> (&({Enum.count(List.first(&1)), Enum.count(List.last(&1))})).()
  end

  # Returns tuple with number of insecure and number of secure
  # requests.
  defp get_request_types(db, visit_id) do
    db
    |> prepare!(
         "SELECT
           (SELECT count(DISTINCT id)
            FROM http_requests
            WHERE visit_id = ?
            AND scheme = 'http')
            AS insecure,
           (SELECT count(DISTINCT id)
            FROM http_requests
            WHERE visit_id = ?
            AND scheme = 'https')
            AS secure")
    |> bind_values!([visit_id, visit_id])
    |> fetch_all!
    |> List.first
    |> Keyword.values
    |> List.to_tuple
  end

  # Returns integer with number of third-party requests.
  defp get_third_party_requests(db, visit_id, base_domain) do
    db
    |> prepare!(
         "SELECT count(DISTINCT base_domain) AS count
          FROM http_requests
          WHERE visit_id = ?
          AND base_domain != ?")
    |> bind_values!([visit_id, base_domain])
    |> fetch_all!
    |> List.first
    |> Keyword.get(:count)
  end

  # Returns map with HTTP headers (in lowercase) and values from the
  # first response from the given site. %{"connection" => "Keep-Alive", ..}
  defp get_headers(db, visit_id) do
    db
    |> prepare!("SELECT headers FROM http_responses WHERE visit_id = ? LIMIT 1")
    |> bind_values!([visit_id])
    |> fetch_all!
    |> List.first
    |> Keyword.get(:headers)
    |> Poison.decode!
    |> Enum.into(%{}, fn([key, value]) -> {String.downcase(key), value} end)
  end

  # Returns string with meta referrer policy, if any, otherwise 0.
  defp get_referrer_policy(site_url) do
    site_url
    |> HTTPoison.get!([], recv_timeout: 30000)
    |> Map.get(:body)
    |> Floki.find("meta[name='referrer']")
    |> Floki.attribute("content")
    |> List.to_string
    |> String.downcase
  end
end
