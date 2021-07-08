from flask_restful import fields

from extensions import db

note_resource_fields = {
    'id': fields.Integer,
    'name': fields.String,
}


class Note(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(500), nullable=False)