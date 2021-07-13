from flask_restful import fields

from extensions import db

tag_resource_fields = {
    'id': fields.Integer,
    'name': fields.String,
}


class Tag(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(30), nullable=False)