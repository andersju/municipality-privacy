/* Code/inspiration borrowed from https://www.tuomassalmi.com/316/
   which in turn is based on code from http://chimera.labs.oreilly.com/books/1230000000345/ch12.html */

var width = 600;
var height = 1000;
var vis = d3.select("#vis").append("svg")
            .attr("width", width).attr("height", height);

var projection = d3.geo.transverseMercator()
                   .rotate([-30,-66,12])
                   .translate([width*1.2, height/5])
                   .scale([4000])

var path = d3.geo.path().projection(projection);

var setColor = function(score) {
  switch (score) {
    case "a":
      return "#1ac81a";
    case "b":
      return "#aec919";
    case "c":
      return "#c8b119";
    case "d":
      return "#c98119";
    case "e":
      return "#c95719";
    default:
      return "8f8f8f";
  }
}

d3.json("kommuner_201608.geojson", function(json) {
  vis.selectAll("path").data(json.features).enter().append("path")
    .attr("d", path)
    .style("fill", function(j) { return setColor(j.properties.kommuner_betyg_score); })
    .style("stroke-width", "1")
    .style("stroke", "black")
    .on("mouseover", function(d) {
      d3.select(this)
        .style("fill", "orange");

      var coordinates = [0, 0];
      coordinates = d3.mouse(this);
      var target = d3.select("#tooltip")
        .style("left", coordinates[0] + "px")
        .style("top", coordinates[1]+20 + "px");

      target.select("#kommun")
        .text(d.properties.KNNAMN);

      target.select("#description")
        .text("Betyg: " + d.properties.kommuner_betyg_score.toUpperCase());

      d3.select("#tooltip").classed("hidden", false);
      d3.select(this).style("cursor", "pointer");
    })
    .on("mouseout", function(d){
      d3.select(this)
        .style("fill", function(j) { return setColor(j.properties.kommuner_betyg_score); })
      d3.select("#tooltip").classed("hidden", true);
      d3.select(this).style("cursor", "default")
    })
    .on("click", function(d) {
      var domain = d.properties.kommuner_betyg_site_url.split('/')[2];
      domain = domain.replace(/^www\./, "");
      window.location = "https://dataskydd.net/kommuner/kommun/" + domain + ".html";
    })
});