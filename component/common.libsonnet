local formatImage = function(img)
  '%(r)s/%(image)s:%(tag)s' % img {
    r: std.get(self, 'repository', std.get(self, 'registry', null)),
  };

{
  formatImage: formatImage,
}
