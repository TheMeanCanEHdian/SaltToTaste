from slugify import slugify


class StringHelper():
    def sanitize_title(self, title):
        return slugify(title)