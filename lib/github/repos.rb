require 'fileutils'
require 'pp'

module GitHubBackup
    module GitHub
        class << self
            attr_accessor :opts
            def options=(v)
                self.opts = v
            end

            def backup_repos()
                # get all repos
                (1..100).each do |i|
                    if opts[:organization]
                      url = "/orgs/#{opts[:organization]}/repos"
                    elsif opts[:passwd]
                      url ="/user/repos"
                    else
                      url = "/users/#{opts[:username]}/repos"
                    end
                    repos = json("#{url}?page=#{i}per_page=100")
                    repos.each do |f|
                        # do we limit to a specific repo?
                        next unless f['name'] == opts[:reponame] if opts[:reponame]
                        backup_repo f
                    end
                    break if repos.size == 0
                end

            end

            def backup_repo(repo)
                Dir.chdir(opts[:bakdir])

                repo['repo_path'] = "#{opts[:bakdir]}/#{repo['name']}"

                clone repo
                fetch_changes repo
                get_forks repo if opts[:forks] and repo['forks'] > 1
                create_all_branches repo if opts[:init_branches]
                dump_issues repo if opts[:issues] && repo['has_issues']
                dump_wiki repo if opts[:wiki] && repo['has_wiki']
                repack repo if opts[:repack]
            end

            def clone(repo)
                if File.exists?(repo['repo_path'])
                    %x{cd #{repo['repo_path']} && git pull origin && cd ..}
                else
                    %x{git clone #{repo['ssh_url']}}
                end
            end

            def fetch_changes(repo)
                Dir.chdir(repo['repo_path'])
                %x{git fetch origin}
                %x{git pull origin}
            end

            def get_forks(repo)
                Dir.chdir(repo['repo_path'])

                # do we get all forks
                (1..100).each do |i|
                    if opts[:organization]
                      url = "/repos/#{opts[:organization]}/#{repo['name']}/forks"
                    else
                      url = "/repos/#{opts[:username]}/#{repo['name']}/forks"
                    end
                    forks = json("#{url}?page=#{i}&per_page=100")
                    forks.each do |f|
                        puts "Adding remote #{f['owner']['login']} from #{f['ssh_url']}.."
                        %x{git remote add #{f['owner']['login']} #{f['ssh_url']} 2> /dev/null}
                        %x{git fetch #{f['owner']['login']}}
                        if File.exists?("../#{f['owner']['login']}__#{repo['name']}")
                            %x{cd ../#{f['owner']['login']}__#{repo['name']} && git pull origin}
                        else
                            %x{cd .. && git clone #{f['ssh_url']} #{f['owner']['login']}__#{repo['name']}}
                        end
                    end
                    break if forks.size == 0
                end
            end

            def create_all_branches(repo)
                Dir.chdir(repo['repo_path'])
                %x{for remote in `git branch -r`; do git branch --track $remote 2> /dev/null; done}
            end

            def dump_issues(repo)
                Dir.chdir(repo['repo_path'])

                filename = repo['repo_path'] + "/issues_dump.txt"
                FileUtils.rm  filename if File.exists?(filename)

                content = ''
                (1..100).each do |i|
                    if opts[:organization]
                      url = "/repos/#{opts[:organization]}/#{repo['name']}/issues"
                    else
                      url = "/repos/#{opts[:username]}/#{repo['name']}/issues"
                    end
                    issues = json("#{url}?page=#{i}&per_page=100")
                    content += issues.join("")
                    break if issues.size == 0
                end

                File.open(filename, 'w') {|f| f.write(content)}
            end

            def dump_wiki(repo)
                Dir.chdir(opts[:bakdir])
                wiki_path = "#{opts[:bakdir]}/#{repo['name']}.wiki"
                %x{git clone git@github.com:#{repo['owner']['login']}/#{repo['name']}.wiki.git} unless File.exists?(wiki_path)
                if File.exists? wiki_path
                    Dir.chdir(wiki_path)
                    %x{git fetch origin}
                end
            end

            def repack(repo)
                Dir.chdir(repo['repo_path'])
                %x{git gc --aggressive --auto}
            end

            def json(url)
                auth = {:username => opts[:username], :password => opts[:passwd]} if opts[:username] and opts[:passwd]
                HTTParty.get('https://api.github.com' << url, :basic_auth => auth, :headers => { "User-Agent" => "Get out of the way, Github" }).parsed_response
            end
        end
    end
end
