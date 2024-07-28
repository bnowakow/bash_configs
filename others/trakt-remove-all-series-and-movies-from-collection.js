
// go to https://trakt.tv/users/supach/collection/shows
// and 
// go to https://trakt.tv/users/supach/collection/movies/added/asc 
// and run:

// https://gist.github.com/alok-mishra/405963a24599b16280f9a535da89133b#file-trakt-remove-all-from-collection-js
// in comments of above gist there're versions that also go through pages as well
$(".posters .grid-item").each(function() {

    function sleep(ms) {
        var start = new Date().getTime(), expire = start + ms;
        while (new Date().getTime() < expire) { }
        return;
    }

    console.log("foo")

    actionWatch($(this).closest('.grid-item'), 'collect', true)
    sleep(10000)
})

