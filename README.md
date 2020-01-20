# SponSkrub
This is a command line utility to strip out in video YouTube advertisements from downloaded YouTube videos, such as those downloaded from [youtube-dl](https://ytdl-org.github.io/youtube-dl/index.html). This means that you both don't waste disk space on adverts and don't redistribute adverts. You can also take advantage of youtube-dl's `--exec` option in order to have SponSkrub run automatically after the video downloads.  

```
youtube-dl -f 18 https://www.youtube.com/watch\?v\=OVWjVQ8mtZ8 --exec "sponskrub OVWjVQ8mtZ8 {} skrubbed-{} && rm {}"
```

It makes use of the [SponsorBlock API](https://github.com/ajayyy/SponsorBlockServer#api-docs) and I'd recommend installing the extension and maybe contributing some sponsorship times when you're ever bored.  
You can build it by running `dub build`.

![before and after SponSkrub](repo_images/before_after.png)
