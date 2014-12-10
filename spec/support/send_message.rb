def send_message(from=@bob, to=@alice, topic="Topic", body="Body")
  from.send_message(to, nil, topic, body)
end
