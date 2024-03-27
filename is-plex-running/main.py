#from plexapi.myplex import MyPlexAccount
#account = MyPlexAccount('bartek@bnowakowski.pl', '')
#plex = account.resource('margok').connect()

from plexapi.server import PlexServer
import traceback


try:
    baseurl = 'http://192.168.0.20:32400'
    password_file = open(".password", "r")
    token = password_file.readline().rstrip()
    plex = PlexServer(baseurl, token)

    #movies=[]
    movies=plex.library.section('Movies').search()
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

except Exception as e:
    print('false,exception,')
    print(e)
    traceback.print_exc()
    

