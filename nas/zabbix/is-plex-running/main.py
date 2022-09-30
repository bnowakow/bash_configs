#from plexapi.myplex import MyPlexAccount
#account = MyPlexAccount('bartek@bnowakowski.pl', '')
#plex = account.resource('margok').connect()

from plexapi.server import PlexServer

try:
    baseurl = 'http://192.168.1.49:32400'
    token = ''
    plex = PlexServer(baseurl, token)

    #movies=[]
    movies=plex.library.section('Films').search()
    #print(len(movies));
    #for video in movies:
    #    print(video.title)

    #tv_series=[]
    tv_series=plex.library.section('TV shows').search()
    #print(len(tv_series));
    #for video in tv_series:
    #    print(video.title)

    if len(movies) + len(tv_series) > 0:
        print('true')
    else:
        print('false,0 movies and tv shows')

except:
    print('false,exception')
    

