defmodule SiteGenerator.Process do
  import SiteGenerator.Helpers
  import Sqlitex.Statement

  def start do
    {:ok, db} = Sqlitex.open("data/crawl-data.sqlite")

    db
    |> Sqlitex.query("SELECT * FROM site_visits ORDER BY municipality_name")
    |> gather_data(db)
    |> render_and_write_sites
    |> render_and_write_index(db)

    render_and_write_pages()

    Sqlitex.close(db)
  end

  defp gather_data({:ok, sites}, db) do
    Enum.reduce(sites, [], fn(site, acc) -> acc ++ [get_site_data(site, db)] end)
  end

  defp get_site_data(site, db) do
    IO.puts "Processing #{site[:visit_id]} (#{site[:site_url]})"
    with base_domain = get_base_domain(site[:site_url]),
         requests    = get_third_party_requests(site[:visit_id], base_domain, db)
    do
      %{name:                  site[:municipality_name],
        url:                   site[:site_url],
        host:                  URI.parse(site[:site_url]).host,
        base_domain:           base_domain,
        score:                 site[:score],
        scheme:                site[:scheme],
        headers:               get_headers(site[:visit_id], db),
        hsts:                  site[:hsts],
        referrer_policy:       site[:referrer_policy],
        meta_referrer:         check_meta_referrer(site[:referrer_policy]),
        cookies:               get_cookies(site[:visit_id], base_domain, db),
        profile_cookies_first: site[:first_party_profile_cookies],
        profile_cookies_third: site[:third_party_profile_cookies],
        session_cookies_first: site[:first_party_session_cookies],
        session_cookies_third: site[:third_party_session_cookies],
        requests:              requests,
        request_types:         get_request_types(requests),
        unique_base_domains:   get_unique_base_domains(requests),
        time_of_visit:         get_time_of_visit(site[:visit_id], db)}
    end
  end

  defp get_cookies(visit_id, base_domain, db) do
    {profile_first, profile_third} =
      db
      |> prepare!("SELECT * FROM profile_cookies WHERE visit_id = ?")
      |> bind_values!([visit_id])
      |> fetch_all!
      |> Enum.partition(&(&1[:baseDomain] == base_domain))

    {session_first, session_third} =
      db
      |> prepare!("SELECT *
                   FROM http_response_cookies
                   WHERE header_id IN
                     (SELECT id FROM http_responses WHERE visit_id = ?)
                   AND expires IS null
                   GROUP BY domain, name")
      |> bind_values!([visit_id])
      |> fetch_all!
      |> Enum.partition(&(&1[:baseDomain] == base_domain))

      {profile_first ++ session_first, profile_third ++ session_third}
  end

  defp get_time_of_visit(visit_id, db) do
    db
    |> prepare!("SELECT time_stamp FROM http_requests WHERE visit_id = ? LIMIT 1")
    |> bind_values!([visit_id])
    |> fetch_all!
    |> List.first
    |> Keyword.get(:time_stamp)
    |> String.slice(0, 19)
  end

  defp get_headers(visit_id, db) do
    db
    |> prepare!("SELECT headers FROM http_responses WHERE visit_id = ? LIMIT 1")
    |> bind_values!([visit_id])
    |> fetch_all!
    |> List.first
    |> Keyword.get(:headers)
    |> Poison.decode!
    |> Enum.reduce(%{}, fn([k, v], acc) -> Map.put(acc, String.downcase(k), v) end)
  end

  defp get_third_party_requests(visit_id, base_domain, db) do
    db
    |> prepare!("SELECT * FROM http_requests WHERE visit_id = ?")
    |> bind_values!([visit_id])
    |> fetch_all!
    |> Enum.reduce(%{}, fn(x, acc) ->
         case get_base_domain(x[:url]) !== base_domain do
           true  -> Map.put(acc, URI.parse(x[:url]).host, x)
           false -> acc
         end
       end)
  end

  defp get_request_types(requests) do
    Enum.reduce(requests, %{:secure => 0, :insecure => 0}, fn({_, req}, acc) ->
      case String.starts_with?(req[:url], "https") do
        true  -> Map.put(acc, :secure, acc[:secure] + 1)
        false -> Map.put(acc, :insecure, acc[:insecure] + 1)
      end
    end)
  end

  defp get_unique_base_domains(requests) do
    requests
    |> Enum.reduce([], fn({_, req}, acc) -> acc ++ [get_base_domain(req[:url])] end)
    |> Enum.uniq
    |> Enum.count
  end

  defp render_and_write_sites(sites) do
    IO.puts "Writing site pages..."
    Enum.each(sites, fn(site) ->
      content =
        EEx.eval_file("templates/app.eex.html",
                      [page: "site", title: "Resultat för #{site[:base_domain]} | Kommunundersökning",
                       data: site, meta: []])
      File.write!("web/kommuner/kommun/#{site[:base_domain]}.html", content)
    end)
    sites
  end

  defp render_and_write_pages do
    IO.puts "Writing static pages..."
    pages = [{"om", "Frågor och svar | Kommunundersökning"},
             {"metodologi", "Metodologi | Kommunundersökning"},
             {"begrepp", "Begrepp & tips | Kommunundersökning"}]

    Enum.each(pages, fn({template, title}) ->
      content = EEx.eval_file("templates/app.eex.html", [page: template, title: title, data: [], meta: []])
      File.write!("web/kommuner/#{template}.html", content)
    end)
  end

  defp render_and_write_index(sites, db) do
    IO.puts "Writing index..."
    scores =
      db
      |> prepare!("SELECT score, COUNT(score) AS value FROM site_visits WHERE score is not null GROUP BY score")
      |> fetch_all!
      |> Enum.map(&({&1[:score], &1[:value]}))
      |> Enum.into(%{})
      |> Map.merge(%{"a" => 0, "b" => 0, "c" => 0, "d" => 0, "e" => 0}, fn(_k, v1, _v2) -> v1 end)

    num_https =
      db
      |> prepare!("SELECT COUNT(scheme) FROM site_visits WHERE scheme == 'https'")
      |> fetch_all!
      |> List.first
      |> Keyword.values
      |> List.first

    stats = %{scores: scores, https: num_https}
    content =
      EEx.eval_file("templates/app.eex.html",
                    [page: "index", title: "Kommunundersökning | dataskydd.net", data: sites, meta: stats])
    File.write!("web/kommuner/index.html", content)
  end
end
