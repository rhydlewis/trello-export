#! /usr/bin/env ruby

# This script depends on the trello gem (https://github.com/jeremytregunna/ruby-trello)
#
# gem install ruby-trello
#

require 'trello'
require 'yaml'
require 'time'
require 'set'

class TrelloExport

  attr_reader :users, :names, :statuses, :board_id

  def initialize(args, stdin)
    settings = YAML.load(File.read('./trello-settings.yaml'))

    Trello.configure do |config|
      config.developer_public_key = settings['api_key']
      config.member_token = settings['token']
    end

    @names = YAML.load(File.read('./users.yaml'))
    @statuses = YAML.load(File.read('./status.yaml'))
    @jira = YAML.load(File.read('./jira.yaml'))
    @board_id = args[0]

    if @board_id == nil
      p 'No board id specified'
      exit 1
    end

  end

  def run
    @users = Set.new
    project = {:name => @jira['project'], :key => @jira['key'], :components => []}
    project[:issues] = parse_cards(@board_id)
    json = {:users => @users.to_a, :links => [], :projects => [project]}.to_json
    File.open(@jira['path'] + "/#{@board_id}_export.json", 'w') { |f| f.write(json) }
  end

  def parse_cards(board_id)
    board = Trello::Board.find(board_id)
    board_name = board.name.gsub(" ", "_")
    cards = board.cards
    issues = []

    total_cards = cards.size
    i = 1

    puts "Exporting board #{board.url} containin #{total_cards.to_s} cards as JSON"

    cards.each { |card|
      created_date = DateTime.strptime(card.id.to_s[0..7].to_i(16).to_s(10), '%s')
      summary = card.name
      reporter = translate_member_name(get_creator(card))
      puts "#{i.to_s}: Exporting #{card.short_url} '#{summary}'"
      issue = {:issueType => "Story", :summary => summary, :status => "Open", :reporter => reporter, :created => created_date}

      description = "#{card.desc}\n\n"
      card.checklists.each { |checklist|
        description = description + "\n\nh2. #{checklist.name}\n\n"
        checklist.check_items.each { |item|
          state = 'OPEN'
          if item['state'].eql?('complete')
            state = 'DONE'
          end
          description = description + "* [#{state}] #{item['name']}\n"
        }
      }

      issue['description'] = description.gsub("####", "h3.").gsub("###", "h2.")

      card.actions.each { |action|
        # puts "#{action.date.to_s}: #{action.data.to_s}"
      }

      issue['comments'] = parse_comments(card)
      issue['status'] = translate_status(find_status(card))
      issue['updated'] = find_last_update(card)

      labels = []
      labels << "import_from_#{board_name}"
      labels.concat(parse_labels(card))

      issue['labels'] = labels

      if issue['status'] != nil
        issues << issue
      else
        puts "WARN: Couldn't find status for #{issue.to_json}"
      end

      i += 1
    }

    issues

  end

  def parse_comments(card)
    comments = []
    card.actions({filter: 'commentCard'}).each { |comment|
      body = comment.data['text']
      created = comment.date
      member = Trello::Member.find(comment.member_creator_id)
      author = translate_member_name(member.username)
      @users.add({"name" => author, "active" => true})
      comments << {"body" => body, "created" => created, "author" => author}
    }
    comments
  end

  def parse_labels(card)
    labels = []
    card.card_labels.each { |label| labels << label['name'] }
    labels
  end

  def find_status(card)
    list = nil
    actions = card.actions({filter: 'updateCard:idList'})

    # puts "Looking for status for #{card.name}"

    if actions.size == 0
      first = card.actions({filter: 'createCard'}).first

      if first.nil?
        first = card.actions({filter: 'copyCard'}).first
      end

      list = first.data['list']['name']
    else
      list = actions.first.data['listAfter']['name']
    end

    list
  end

  def find_last_update(card)
    updated = nil
    actions = card.actions({filter: 'updateCard:idList'})

    if actions.size == 0

      first = card.actions({filter: 'createCard'}).first

      if first.nil?
        first = card.actions({filter: 'copyCard'}).first
      end

      updated = first.date
    else
      updated = actions.first.date
    end

    updated
  end

  def translate_member_name(name)
    mapped_name = @names[name]
    # puts "Looking for #{name}, found #{mapped_name}"
    mapped_name unless mapped_name == nil
  end

  def translate_status(status)
    mapped_status = @statuses[status]
    # puts "Looking for #{status}, found #{mapped_status}"
    mapped_status unless mapped_status == nil
  end

  def get_creator(card)
    creator = ''
    actions = card.actions({filter: 'createCard'})

    if actions.size == 0
      actions = card.actions({filter: 'moveCardToBoard'})
    end

    if actions.size == 0
      actions = card.actions({filter: 'copyCard'})
    end

    action = actions[0]
    creator_id = action.member_creator_id
    if creator_id != nil
      member = Trello::Member.find(action.member_creator_id)
      creator = member.username
    end
    creator
  end

  # def get_card
  #   card = Trello::Card.find("???")
  #   puts "creator: " + get_creator(card)
  #   puts "labels: " + parse_labels(card).to_s
  #   puts "status: " + translate_status(find_status(card))
  #   puts card.actions.to_json
  # end

end

app = TrelloExport.new(ARGV, STDIN)
app.run





