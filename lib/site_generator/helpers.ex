defmodule SiteGenerator.Helpers do
  def format_timestamp(time) do
    # Sites occasionally set cookies with insane expiration times (> 9999-12-31 23:59:59),
    # which DateTime balks at. In those cases, we forcibly set the time to 9999-12-31 23:59:59.
    time
    |> case do
         timestamp when timestamp > 253402300799 -> 253402300799
         timestamp -> timestamp
       end
    |> round
    |> DateTime.from_unix!
    |> DateTime.to_naive
    |> NaiveDateTime.to_string
  end

  def format_datetime({{year, month, day}, {hour, minute, second, _microsecond}}) do
    format_datetime({{year, month, day}, {hour, minute, second}})
  end
  def format_datetime({{year, month, day}, {hour, minute, second}}) do
    year =
      case year do
        year when year > 9999 -> 9999
        year -> year
      end
    {:ok, date} = NaiveDateTime.new(year, month, day, hour, minute, second)
    NaiveDateTime.to_string(date)
  end

  def get_base_domain(url) do
    with host = URI.parse(url).host, base_domain = PublicSuffix.registrable_domain(host)
    do
      case base_domain do
        nil -> host
        _   -> base_domain
      end
    end
  end

  def truncate(string, maximum) do
    if String.length(string) > maximum do
      "#{String.slice(string, 0, maximum)}..."
    else
      string
    end
  end

  def headers_to_check do
    %{
      "Strict-Transport-Security" =>
        ~s{<a href="https://https.cio.gov/hsts/">HTTP Strict Transport Security</a> (HSTS) skyddar besökare genom att se till att deras webbläsare alltid ansluter över HTTPS.},
      "Content-Security-Policy" =>
        ~s{<a href="https://scotthelme.co.uk/content-security-policy-an-introduction/">Content Security Policy</a> (CSP) är ett kraftfullt verktyg för att skydda en webbplats mot till exempel XSS-attacker och informationsläckage. },
      "X-Frame-Options" =>
        ~s{Med X-Frame-Options kan servern berätta för webbläsaren huruvida sidan får visas i en <code>&lt;frame&gt;</code>, <code>&lt;iframe&gt;</code> eller <code>&lt;object&gt;</code>. Med andra ord: det är möjligt att säga att sidan inte får bäddas in i en annan sajt. Detta skyddar mot så kallad <a href="https://en.wikipedia.org/wiki/Clickjacking">clickjacking</a>.},
      "X-Xss-Protection" =>
        ~s{X-XSS-Protection ställer in <a href="https://en.wikipedia.org/wiki/Cross-site_scripting">XSS</a>-filtret i en del webbläsare. <a href="https://scotthelme.co.uk/hardening-your-http-response-headers/#x-xss-protection">Rekommenderat värde</a> är <code>X-XSS-Protection: 1; mode=block</code>.},
      "X-Content-Type-Options" =>
        ~s{X-Content-Type-Options <a href="https://scotthelme.co.uk/hardening-your-http-response-headers/#x-content-type-options">skyddar mot en viss typ av attacker</a> och dess enda giltiga värde är <code>X-Content-Type-Options: nosniff</code>.}
    }
  end

  def check_referrer_policy(referrer) do
    cond do
      referrer in ["never", "no-referrer"] ->
        %{"status" => "success",
          "icon"   => "icon-umbrella2 success",
          "text"   => "Referrers läcks ej"}
      referrer in ["origin", "origin-when-cross-origin", "origin-when-crossorigin"] ->
        %{"status" => "warning",
          "icon"   => "icon-raindrops2 warning",
           "text"  => "Referrers läcks delvis"}
      referrer in ["no-referrer-when-down-grade", "default", "unsafe-url", "always", "", nil] ->
        %{"status" => "alert",
          "icon" => "icon-raindrops2 alert",
           "text" => "Referrers läcks"}
      true ->
        %{"status" => "other",
          "icon" => "",
          "text" => "Referrers läcks (antagligen)"}
    end
  end
end
