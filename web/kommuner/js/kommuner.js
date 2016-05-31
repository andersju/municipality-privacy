$(document).ready( function () {
    $('.datatable').DataTable({
      fixedHeader: true,
      pageLength: 25,
      language: {
              processing:     "Laddar...",
              search:         "Sök&nbsp;:",
              lengthMenu:     "Visa _MENU_ kommuner",
              info:           "Visar _START_ till _END_ av _TOTAL_ kommuner",
              infoEmpty:      "Visar 0 till 0 av 0 kommuner",
              infoFiltered:   "(filtrerat från totalt _MAX_ kommuner)",
              infoPostFix:    "",
              zeroRecords:    "Inga matchande kommuner hittades",
              loadingRecords: "Laddar...",
              paginate: {
                  first:      "Första",
                  previous:   "Föregående",
                  next:       "Nästa",
                  last:       "Sista"
              },
              aria: {
                  sortAscending:  ": aktivera för att sortera ökande",
                  sortDescending: ": aktivera för att sortera minskande"
              }
          }
    });
} );